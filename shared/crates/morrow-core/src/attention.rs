//! The attention policy (`AttentionPolicy`, `Sources/MorrowCore/AttentionPolicy.swift`)
//! and the sound routing it reads (`EventSoundRouting.swift`): what a moment
//! calls for on its own — a sound, a completion card, a push, a follow-up
//! reminder — given the session it happened to.
//!
//! [`intents`] is the port; every rule here has a row in
//! `fixtures/core/attention.json`. `settle(_:context:)` — the user's sound
//! switches, quiet hours, the lock screen, the completion style, Smart
//! Suppress — is not ported: it reads settings and scene facts that arrive
//! with the `morrow-platform` adapters (plan §5.2) and no fixture covers it.
//! Until then a shell settles what it has in its own outlets.

use crate::reduce::{HookEventFacts, SessionSnapshot};

/// `SoundCue`: the sound cues the policy speaks in, as `SoundManager` keys
/// its sounds and the per-event switches.
pub mod sound_cue {
    /// An approval or a question needs the user ("approval needed").
    pub const REQUEST: &str = "PermissionRequest";
    pub const SESSION_START: &str = "SessionStart";
    pub const PROMPT: &str = "UserPromptSubmit";
    /// A turn finished.
    pub const TURN_END: &str = "Stop";
    /// The app was launched by the user.
    pub const LAUNCH: &str = "AppLaunch";
}

/// `EventSoundRouting.turnFailed`: the cue for a turn that died on an error.
/// The name follows Claude Code's hook.
pub const TURN_FAILED: &str = "StopFailure";

/// `EventSoundRouting.soundEvent(rawEventName:normalizedEventName:)`: the cue
/// a hook event rings, or `None` when it stays silent.
///
/// Sounds mark turn boundaries, not steps inside a turn: a failed tool call
/// is routine. `StopFailure` is only visible before `EventNormalizer` folds
/// it onto `Stop`, which is why the raw name comes along.
pub fn sound_event(raw_event_name: &str, normalized_event_name: &str) -> Option<String> {
    if normalized_event_name == "PostToolUseFailure" {
        return None;
    }
    // The launch chime's cue is the app's own: a hook event that happens to
    // carry its name rings nothing.
    if normalized_event_name == sound_cue::LAUNCH {
        return None;
    }
    if raw_event_name == "StopFailure" || raw_event_name == "stop_failure" {
        return Some(TURN_FAILED.to_owned());
    }
    Some(normalized_event_name.to_owned())
}

/// Something that happened which may deserve the user's attention.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum AttentionMoment {
    /// A hook event, as the reducer applied it.
    HookEvent(HookEventFacts),
    /// The island queued an approval. `first_of_burst`: no other approval was
    /// visibly waiting (a dismissed one does not count).
    ApprovalQueued { first_of_burst: bool },
    /// The island queued a question. `smart_suppressible`: false for Codex
    /// Desktop's app-server question, whose card and push have never been
    /// held back by Smart Suppress.
    QuestionQueued {
        first_of_burst: bool,
        smart_suppressible: bool,
    },
    /// An agent got blocked on the user somewhere the island cannot answer
    /// for it (`DisplayOnlyWait`).
    RequestRaisedElsewhere,
    /// A session began waiting display-only on `kind`. `announce`: a live
    /// wait from a source the island can never own, rather than a launch
    /// rebuild, a backfill, or a terminal prompt the island may still queue.
    DisplayOnlyWaitBegan {
        kind: FollowUpReminderKind,
        announce: bool,
    },
    /// A turn began in a source the hook reducer never sees.
    TurnStarted { new_session: bool },
    /// A turn ended in a source the hook reducer never sees.
    TurnEnded { end: TurnEnd, host: TurnHost },
    /// A follow-up reminder came due and the island itself delivers it.
    ReminderDue {
        kind: FollowUpReminderKind,
        turn_failed: bool,
    },
    /// The user launched the app (a launch at login stays silent before it
    /// gets here).
    AppLaunched,
}

/// How a turn ended in a source that bypasses the hook reducer.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TurnEnd {
    Completed,
    /// On an error: a failed AiWork stream, a Cowork turn whose result is an
    /// error.
    Failed,
    /// The user stopped it: Claude Desktop's Stop button, AiWork's
    /// `stream.aborted`.
    Stopped,
}

/// Where a turn that bypasses the hook reducer ran.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TurnHost {
    /// Claude Desktop (Cowork tasks), read from its session store.
    ClaudeDesktop,
    /// An AiWork / Agentix daemon (`sessions.watch`).
    Aiwork,
}

/// `FollowUpReminderKind`: what a session was waiting for when its reminders
/// started.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FollowUpReminderKind {
    Approval,
    Question,
    Completion,
}

impl FollowUpReminderKind {
    /// The case name the fixtures and the frontend use.
    pub fn raw_value(self) -> &'static str {
        match self {
            Self::Approval => "approval",
            Self::Question => "question",
            Self::Completion => "completion",
        }
    }

    pub fn from_raw_value(value: &str) -> Option<Self> {
        match value {
            "approval" => Some(Self::Approval),
            "question" => Some(Self::Question),
            "completion" => Some(Self::Completion),
            _ => None,
        }
    }
}

/// What the rules read about the session a moment happened to.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct AttentionSubject {
    /// The session is a child another agent spawned, working for its parent:
    /// it names one (`SessionSnapshot.parent_session_id`), or the app just
    /// folded its card into its parent's.
    pub is_child: bool,
    /// The user stopped the session's turn (Esc / Ctrl-C).
    pub interrupted: bool,
}

impl AttentionSubject {
    /// As `session` stands; a session the island no longer holds is nobody's
    /// child.
    pub fn from_session(session: Option<&SessionSnapshot>) -> Self {
        Self {
            is_child: session.is_some_and(|s| s.parent_session_id.is_some()),
            interrupted: session.is_some_and(|s| s.interrupted),
        }
    }
}

/// What a push is about.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum AttentionPushKind {
    /// The turn ended on an error.
    Error,
    /// The turn finished. A subagent's or an interrupted one is offered to
    /// the push gate all the same: it turns both away and says why.
    Completion {
        is_subagent: bool,
        interrupted: bool,
    },
    Approval,
    Question,
    /// A display-only wait began: answer it where it was asked.
    DisplayOnlyWait,
}

/// Follow-up reminder bookkeeping a moment starts.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum FollowUpIntent {
    /// One nudge for this finished turn if nobody looks at it.
    TrackCompletion { turn_failed: bool },
    /// A display-only wait began: its reminders start over.
    RestartWait(FollowUpReminderKind),
}

/// What a moment calls for.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct AttentionIntents {
    /// The sound cue (a [`sound_cue`] or a hook event's name), or `None`.
    pub sound: Option<String>,
    /// The moment finished a turn the island announces.
    pub completion: Option<Completion>,
    pub push: Option<Push>,
    pub follow_up: Option<FollowUpIntent>,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Completion {
    pub turn_failed: bool,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Push {
    pub kind: AttentionPushKind,
    /// Smart Suppress may hold it back while the user is at the machine.
    pub smart_suppressible: bool,
}

/// `AttentionPolicy.intents(for:subject:)`: what `moment` calls for, before
/// the user's settings and the room have their say.
pub fn intents(moment: &AttentionMoment, subject: AttentionSubject) -> AttentionIntents {
    let sound = |cue: &str| AttentionIntents {
        sound: Some(cue.to_owned()),
        ..AttentionIntents::default()
    };
    match moment {
        AttentionMoment::HookEvent(facts) => hook_event_intents(facts, subject),
        AttentionMoment::ApprovalQueued { first_of_burst } => {
            // The chime marks the start of a burst of approvals: three queued
            // back to back are one interruption, not three. The push is per
            // request; its dedupe tells replays apart.
            AttentionIntents {
                sound: first_of_burst.then(|| sound_cue::REQUEST.to_owned()),
                push: Some(Push {
                    kind: AttentionPushKind::Approval,
                    smart_suppressible: true,
                }),
                ..AttentionIntents::default()
            }
        }
        AttentionMoment::QuestionQueued {
            first_of_burst,
            smart_suppressible,
        } => AttentionIntents {
            sound: first_of_burst.then(|| sound_cue::REQUEST.to_owned()),
            push: Some(Push {
                kind: AttentionPushKind::Question,
                smart_suppressible: *smart_suppressible,
            }),
            ..AttentionIntents::default()
        },
        // Nothing is queued — the answer can only be given where it was
        // asked — so the sound is what says the agent is blocked.
        AttentionMoment::RequestRaisedElsewhere => sound(sound_cue::REQUEST),
        // Reminders start over for every wait that begins. Only a live wait
        // from a source the island can never own is pushed: a launch rebuild
        // or a backfill is old news, and a terminal `permission_prompt`
        // races its own PermissionRequest hook, whose richer push would lose
        // its dedupe slot to this one.
        AttentionMoment::DisplayOnlyWaitBegan { kind, announce } => AttentionIntents {
            push: announce.then_some(Push {
                kind: AttentionPushKind::DisplayOnlyWait,
                smart_suppressible: true,
            }),
            follow_up: Some(FollowUpIntent::RestartWait(*kind)),
            ..AttentionIntents::default()
        },
        AttentionMoment::TurnStarted { new_session } => {
            if subject.is_child {
                return AttentionIntents::default();
            }
            sound(if *new_session {
                sound_cue::SESSION_START
            } else {
                sound_cue::PROMPT
            })
        }
        AttentionMoment::TurnEnded { end, host } => {
            if subject.is_child {
                return AttentionIntents::default();
            }
            match end {
                TurnEnd::Completed => finished_turn_intents(false, subject),
                TurnEnd::Failed => finished_turn_intents(true, subject),
                // Claude Desktop's Stop button: the user is right there and
                // knows. No jingle, no completion card, no push, no
                // follow-up; the card just reads interrupted.
                TurnEnd::Stopped => match host {
                    TurnHost::ClaudeDesktop => AttentionIntents::default(),
                    // `stream.aborted` has always popped its card (it reads
                    // "interrupted"), like an Esc in a hook-driven agent —
                    // but it rings nothing, pushes nothing and is not
                    // followed up.
                    TurnHost::Aiwork => AttentionIntents {
                        completion: Some(Completion { turn_failed: false }),
                        ..AttentionIntents::default()
                    },
                },
            }
        }
        // The same sound as the moment it reminds of: a turn that died rings
        // the error jingle again, not "done".
        AttentionMoment::ReminderDue { kind, turn_failed } => match kind {
            FollowUpReminderKind::Approval | FollowUpReminderKind::Question => {
                sound(sound_cue::REQUEST)
            }
            FollowUpReminderKind::Completion => sound(if *turn_failed {
                TURN_FAILED
            } else {
                sound_cue::TURN_END
            }),
        },
        AttentionMoment::AppLaunched => sound(sound_cue::LAUNCH),
    }
}

fn hook_event_intents(facts: &HookEventFacts, subject: AttentionSubject) -> AttentionIntents {
    // A session another agent spawned works for that agent's turn: its own
    // start, prompt, turn end and failure are the parent's business, not the
    // user's. Its approvals and questions arrive as their own moments and
    // still alert.
    if subject.is_child {
        return AttentionIntents::default();
    }
    // A conversation held somewhere else — a Hermes gateway chat, the API
    // server, a background run: its card follows along, but a bot answering
    // on Telegram isn't news at the desk.
    if facts.held_elsewhere {
        return AttentionIntents::default();
    }

    let cue = sound_event(&facts.raw_event_name, &facts.event_name);
    let mut intents = AttentionIntents::default();
    // Only an event that moved the session itself rings: not one dropped as
    // stale, filed under a subagent, or ending the session. A turn the user
    // stopped ends without a chime: it did not complete, and the user knows —
    // its card still pops.
    if facts.applied_to_session && !(facts.ended_turn && subject.interrupted) {
        intents.sound = cue.clone();
    }
    if facts.ended_turn {
        // The normalizer folds StopFailure onto Stop; only the raw name says
        // the turn died (same rule as its sound).
        let turn_failed = cue.as_deref() == Some(TURN_FAILED);
        intents.completion = Some(Completion { turn_failed });
        intents.follow_up = follow_up(turn_failed, subject);
    }
    // A turn that stopped on an error pushes the error instead of a
    // completion: one push for one failed turn. Only the session's own turn,
    // though: a subagent's failure filed under the session (or a stale one)
    // is not its error, and pushed under its name it would shadow the
    // session's own completion push a moment later.
    if facts.turn_error.is_some() {
        if facts.applied_to_session {
            intents.push = Some(Push {
                kind: AttentionPushKind::Error,
                smart_suppressible: true,
            });
        }
    } else if facts.ended_turn {
        intents.push = Some(Push {
            kind: AttentionPushKind::Completion {
                is_subagent: facts.subagent_turn,
                interrupted: subject.interrupted,
            },
            smart_suppressible: true,
        });
    }
    intents
}

/// A turn that finished in a source the hook reducer never sees. One the user
/// stopped ends without a chime there too.
fn finished_turn_intents(turn_failed: bool, subject: AttentionSubject) -> AttentionIntents {
    AttentionIntents {
        sound: (!subject.interrupted).then(|| {
            if turn_failed {
                TURN_FAILED
            } else {
                sound_cue::TURN_END
            }
            .to_owned()
        }),
        completion: Some(Completion { turn_failed }),
        push: Some(Push {
            kind: if turn_failed {
                AttentionPushKind::Error
            } else {
                AttentionPushKind::Completion {
                    is_subagent: false,
                    interrupted: subject.interrupted,
                }
            },
            smart_suppressible: true,
        }),
        follow_up: follow_up(turn_failed, subject),
    }
}

/// One nudge for a finished turn nobody looked at — unless the user stopped
/// it themselves: an interrupted turn is not news to anyone.
fn follow_up(turn_failed: bool, subject: AttentionSubject) -> Option<FollowUpIntent> {
    (!subject.interrupted).then_some(FollowUpIntent::TrackCompletion { turn_failed })
}
