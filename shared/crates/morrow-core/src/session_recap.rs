//! Claude Code's "while you were away" recap (`SessionRecap`,
//! `macos/Sources/MorrowCore/SessionRecap.swift`).
//!
//! A few minutes after a turn goes idle Claude Code appends
//! `{"type":"system","subtype":"away_summary","content":"…","timestamp":"…"}`
//! to the transcript: one or two sentences on what got done and what is
//! waiting on the user. The card shows it on idle cards until a newer user
//! prompt starts another turn.

use serde_json::{Map, Value};

use crate::reduce::Timestamp;
use crate::time::parse_iso8601;

#[derive(Clone, Debug, PartialEq)]
pub struct SessionRecap {
    pub text: String,
    /// When Claude Code wrote the recap (the line's `timestamp`), falling back
    /// to the moment it was observed (the caller's clock).
    pub created_at: Timestamp,
}

impl SessionRecap {
    pub fn new(text: impl Into<String>, created_at: Timestamp) -> Self {
        Self {
            text: text.into(),
            created_at,
        }
    }

    /// A prompt submitted at or after the recap was written starts a new turn.
    pub fn is_superseded(&self, prompt_at: Timestamp) -> bool {
        prompt_at.0 >= self.created_at.0
    }

    /// Build from a parsed transcript line, or `None` when it is not a usable
    /// main-thread `away_summary`.
    pub fn from_transcript_line(json: &Map<String, Value>, observed_at: Timestamp) -> Option<Self> {
        if json.get("subtype").and_then(Value::as_str) != Some("away_summary") {
            return None;
        }
        if json.get("isSidechain") == Some(&Value::Bool(true)) {
            return None;
        }
        let text = Self::cleaned_text(json.get("content"))?;
        let created_at = json
            .get("timestamp")
            .and_then(Value::as_str)
            .and_then(parse_iso8601)
            .unwrap_or(observed_at);
        Some(Self { text, created_at })
    }

    /// Trim the raw `content` and drop the "(disable recaps in /config)" hint
    /// the CLI appends for its own TUI — an instruction for the terminal, not
    /// part of the summary. Matched on "/config" inside a trailing
    /// parenthetical so other CLI languages and wordings are covered too.
    pub fn cleaned_text(raw: Option<&Value>) -> Option<String> {
        let mut text = raw?.as_str()?.trim().to_owned();
        if text.is_empty() {
            return None;
        }
        if text.ends_with(')') {
            if let Some(open) = text.rfind('(') {
                if text[open..].contains("/config") {
                    text = text[..open].trim().to_owned();
                }
            }
        }
        (!text.is_empty()).then_some(text)
    }
}

// MARK: - Absorbing a delta

use crate::model_label::{self, ModelObservation};
use crate::reduce::{SessionSnapshot, SubagentState};
use crate::transcript::ScanDelta;

impl SessionSnapshot {
    /// A new user prompt makes an older recap stale.
    pub fn clear_recap_if_superseded(&mut self, prompt_at: Timestamp) {
        if let Some(recap) = &self.recap {
            if recap.is_superseded(prompt_at) {
                self.recap = None;
            }
        }
    }

    /// Apply the recap / model fields of a live transcript tail delta.
    ///
    /// Returns true when anything changed. Deliberately leaves `last_activity`
    /// alone: a recap lands minutes after the turn ended and is not agent
    /// activity, so it must not reorder cards or postpone idle cleanup.
    pub fn apply_transcript_delta(&mut self, delta: &ScanDelta) -> bool {
        self.apply_transcript_metadata(
            delta.session_recap.clone(),
            delta.last_user_prompt.is_some(),
            delta.model_observation.clone(),
            delta.configured_long_context,
            false,
        )
    }

    /// Attach-time backfill from a scan of the transcript's tail.
    ///
    /// The scan is authoritative for the recap: a fresh recap is always within
    /// the tail (only small bookkeeping lines follow one until the next
    /// prompt), so "no recap in the tail" means a restored or persisted recap
    /// went stale while nobody was watching. It is *not* authoritative for a
    /// model a hook reported after the scanned lines were written (see
    /// [`apply_backfilled_model_observation`](Self::apply_backfilled_model_observation)).
    pub fn apply_transcript_backfill(&mut self, scan: &ScanDelta) -> bool {
        self.apply_transcript_metadata(
            scan.session_recap.clone(),
            scan.last_user_prompt.is_some(),
            scan.model_observation.clone(),
            scan.configured_long_context,
            true,
        )
    }

    /// A model/effort read from transcript history (not a live line): it
    /// yields to a model a hook reported after that line was written —
    /// `claude --resume --model X` over a transcript that ran on Y keeps X,
    /// and takes the line's effort only when the line was on X too.
    pub fn apply_backfilled_model_observation(&mut self, observation: &ModelObservation) -> bool {
        self.apply_model_observation(observation, true)
    }

    fn apply_transcript_metadata(
        &mut self,
        new_recap: Option<SessionRecap>,
        saw_user_prompt: bool,
        model_observation: Option<ModelObservation>,
        long_context_switch: Option<bool>,
        is_backfill: bool,
    ) -> bool {
        let mut changed = false;
        // The scan only reports a recap that no later prompt in the same chunk
        // superseded, and every line in the chunk postdates what we already
        // hold — so a prompt clears the old recap and a chunk recap replaces
        // it.
        let resolved_recap = match new_recap {
            Some(recap) => Some(recap),
            None if saw_user_prompt || is_backfill => None,
            None => self.recap.clone(),
        };
        if resolved_recap != self.recap {
            self.recap = resolved_recap;
            changed = true;
        }

        // A `/model` switch to or from the 1M variant. From history, only while
        // no hook has reported the model since: that report is newer.
        if let Some(long_context) = long_context_switch {
            if !(is_backfill && self.model_reported_at.is_some()) {
                self.configured_long_context = Some(long_context);
                if let Some(current) = self.model.clone() {
                    let switched = model_label::with_long_context(&current, long_context);
                    if switched != current {
                        self.model = Some(switched);
                        changed = true;
                    }
                }
            }
        }

        if let Some(observation) = model_observation {
            if self.apply_model_observation(&observation, is_backfill) {
                changed = true;
            }
        }
        changed
    }

    fn apply_model_observation(
        &mut self,
        observation: &ModelObservation,
        is_backfill: bool,
    ) -> bool {
        if is_backfill {
            if let Some(reported_at) = self.model_reported_at {
                if observation
                    .observed_at()
                    .unwrap_or(Timestamp(f64::NEG_INFINITY))
                    < reported_at
                {
                    if !model_label::is_same_model(self.model.as_deref(), &observation.model)
                        || observation.effort == self.reasoning_effort
                    {
                        return false;
                    }
                    self.reasoning_effort = observation.effort.clone();
                    return true;
                }
            }
        }
        let mut changed = false;
        // Transcript lines carry the bare API id; after a `/model` switch its
        // word on the 1M variant decides the decoration, otherwise a
        // hook-reported `[1m]` id of the same model survives.
        let merged_model = match self.configured_long_context {
            Some(long_context) => model_label::with_long_context(&observation.model, long_context),
            None => model_label::merged_model_id(self.model.as_deref(), &observation.model),
        };
        if self.model.as_deref() != Some(merged_model.as_str()) {
            self.model = Some(merged_model);
            changed = true;
        }
        if observation.effort != self.reasoning_effort {
            self.reasoning_effort = observation.effort.clone();
            changed = true;
        }
        changed
    }

    /// Recap to show on the card: only while the session is idle — a working
    /// session's live output is more current than any summary of the past.
    pub fn visible_recap(&self) -> Option<&SessionRecap> {
        if self.status == crate::reduce::AgentStatus::Idle {
            self.recap.as_ref()
        } else {
            None
        }
    }

    /// "Opus 5.5 · xhigh" for the card's model tag.
    pub fn model_label(&self) -> Option<String> {
        model_label::label(self.model.as_deref(), self.reasoning_effort.as_deref())
    }
}

impl SubagentState {
    /// A Claude subagent's own transcript, derived from the parent's:
    /// `<project>/<session>.jsonl` → `<project>/<session>/subagents/agent-<id>.jsonl`.
    /// Claude Code hooks never say which model a subagent runs, so this file is
    /// the only place its model (which may differ from the parent's) is recorded.
    pub fn claude_transcript_path(parent_transcript_path: &str, agent_id: &str) -> Option<String> {
        let suffix = ".jsonl";
        let session_dir = parent_transcript_path.strip_suffix(suffix)?;
        if agent_id.is_empty() || agent_id.contains('/') || agent_id.contains("..") {
            return None;
        }
        Some(format!("{session_dir}/subagents/agent-{agent_id}.jsonl"))
    }

    /// Label for the subagent's own model, never the parent's.
    pub fn model_label(&self) -> Option<String> {
        model_label::label(self.model.as_deref(), self.reasoning_effort.as_deref())
    }
}
