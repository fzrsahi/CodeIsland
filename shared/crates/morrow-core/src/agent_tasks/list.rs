//! An agent's own task checklist (`AgentTaskList`,
//! `macos/Sources/MorrowCore/AgentTaskList.swift:227-684`).
//!
//! A pure value: the reducer applies hook events to it and the shell applies
//! transcript events, both through [`AgentTaskList::apply`]. Only `items` and
//! `completed_at` are visible to callers (and persisted); the dedupe and undo
//! bookkeeping is rebuilt from the transcript on relaunch.

use std::collections::{BTreeMap, BTreeSet};

use serde_json::{Map, Value, json};

use super::{AgentTaskChange, AgentTaskEvent, AgentTaskItem, AgentTaskRowPatch, AgentTaskStatus};
use crate::reduce::Timestamp;

/// Bounds for pathological input; real checklists are a handful of rows.
const MAX_ITEMS: usize = 100;
const MAX_APPLIED_OP_KEYS: usize = 512;
const MAX_PARKED_CHANGES: usize = 64;
const MAX_UNDO_ENTRIES: usize = 64;
const MAX_TITLE_LENGTH: usize = 200;

/// How long a fully completed list stays on the card before it fades.
pub const COMPLETED_LINGER: f64 = 8.0;

/// A turn shorter than this can't count as "a turn without the plan": the
/// other channel's late end of the *previous* turn lands right after the next
/// one starts (Codex runs a queued prompt back to back).
const MIN_UNTOUCHED_TURN_DURATION: f64 = 3.0;

#[derive(Clone, Debug, Default, PartialEq, Eq)]
struct ParkedChange {
    op_id: Option<String>,
    change: AgentTaskChange,
}

#[derive(Clone, Debug, PartialEq, Eq)]
struct UndoEntry {
    before: AgentTaskItem,
    /// `None` when the op deleted the row.
    after: Option<AgentTaskItem>,
    index: usize,
}

#[derive(Clone, Debug)]
pub struct AgentTaskList {
    pub items: Vec<AgentTaskItem>,
    /// When every item last became completed; `None` while any item is open.
    /// The card keeps a finished list up briefly, then lets it go (see
    /// [`is_visible`](Self::is_visible)) — no timer involved.
    completed_at: Option<Timestamp>,

    // Transient bookkeeping (not persisted).
    applied_op_keys: Vec<String>,
    applied_op_key_set: BTreeSet<String>,
    /// Updates for a task whose TaskCreate result has not arrived yet
    /// (Claude's async PostToolUse can land after the next TaskUpdate's
    /// PreToolUse).
    parked_changes: BTreeMap<String, ParkedChange>,
    /// What each recent update replaced, so a failed call can be undone.
    undo_journal: BTreeMap<String, UndoEntry>,
    undo_journal_order: Vec<String>,

    // Turn tracking, for retiring a snapshot plan the agent stopped updating.
    // Hooks and the transcript both report turn boundaries, in no guaranteed
    // order relative to each other, so repeats of an open or close are ignored.
    turn_open: bool,
    turn_started_at: Option<Timestamp>,
    /// Whether the list was touched since the current turn began. Starts true
    /// so a restored list isn't retired before a whole turn has been seen.
    touched_this_turn: bool,
    /// A whole turn went by without touching the list.
    saw_untouched_turn: bool,
    /// Set while [`rebuilt`](Self::rebuilt) replays one transcript: a single,
    /// ordered channel stamped the distant past, where durations mean nothing.
    is_replaying: bool,
}

impl Default for AgentTaskList {
    fn default() -> Self {
        Self {
            items: Vec::new(),
            completed_at: None,
            applied_op_keys: Vec::new(),
            applied_op_key_set: BTreeSet::new(),
            parked_changes: BTreeMap::new(),
            undo_journal: BTreeMap::new(),
            undo_journal_order: Vec::new(),
            turn_open: false,
            turn_started_at: None,
            // A restored list must not be retired before a whole turn has been
            // seen.
            touched_this_turn: true,
            saw_untouched_turn: false,
            is_replaying: false,
        }
    }
}

impl AgentTaskList {
    pub fn new() -> Self {
        Self::default()
    }

    /// Restore a persisted list (or build a preview).
    pub fn restored(items: Vec<AgentTaskItem>, completed_at: Option<Timestamp>) -> Self {
        Self {
            items: items.into_iter().take(MAX_ITEMS).collect(),
            completed_at,
            ..Self::default()
        }
    }

    // MARK: Derived state

    pub fn completed_at(&self) -> Option<Timestamp> {
        self.completed_at
    }

    pub fn is_empty(&self) -> bool {
        self.items.is_empty()
    }

    pub fn completed_count(&self) -> usize {
        self.items
            .iter()
            .filter(|item| item.status == AgentTaskStatus::Completed)
            .count()
    }

    pub fn is_all_completed(&self) -> bool {
        !self.items.is_empty()
            && self
                .items
                .iter()
                .all(|item| item.status == AgentTaskStatus::Completed)
    }

    /// The row being worked on right now (first in-progress one).
    pub fn current(&self) -> Option<&AgentTaskItem> {
        self.items
            .iter()
            .find(|item| item.status == AgentTaskStatus::InProgress)
    }

    /// A whole-list snapshot (TodoWrite, update_plan, write_todos) rather than
    /// Claude's TaskCreate tasks, which live on in the CLI's own task store.
    pub fn is_snapshot_list(&self) -> bool {
        !self.items.is_empty() && self.items.iter().all(|item| item.id.starts_with("step:"))
    }

    /// When a fully completed list should leave the card; `None` while open.
    pub fn hide_deadline(&self, linger: f64) -> Option<Timestamp> {
        if !self.is_all_completed() {
            return None;
        }
        self.completed_at
            .map(|finished| Timestamp(finished.0 + linger))
    }

    /// Show the compact row? Open lists always; finished ones only until
    /// [`hide_deadline`](Self::hide_deadline).
    pub fn is_visible(&self, now: Timestamp, linger: f64) -> bool {
        if self.items.is_empty() {
            return false;
        }
        match self.hide_deadline(linger) {
            None => true,
            Some(deadline) => now.0 < deadline.0,
        }
    }

    // MARK: Applying events

    /// Apply events in order. Returns whether the visible list changed.
    pub fn apply_all(&mut self, events: &[AgentTaskEvent], now: Timestamp) -> bool {
        let mut changed = false;
        for event in events {
            if self.apply(event, now) {
                changed = true;
            }
        }
        changed
    }

    /// Apply one event. Returns whether the visible list changed.
    pub fn apply(&mut self, event: &AgentTaskEvent, now: Timestamp) -> bool {
        // Nothing for a text-only result to complete: leave its op key free, so
        // the call's structured result (a hook) still lands if it follows.
        if let AgentTaskEvent::CreatedPerText { op_id, .. } = event {
            if !self
                .items
                .iter()
                .any(|item| item.create_op_id.as_deref() == Some(op_id.as_str()))
            {
                return false;
            }
        }
        if let Some(key) = event.dedupe_key() {
            if self.applied_op_key_set.contains(&key) {
                return false;
            }
            self.record_applied(key);
        }

        let before = self.items.clone();
        match event {
            AgentTaskEvent::NewTurn => {
                // A new prompt retires a finished checklist. An unfinished one
                // is normally still the agent's plan and stays — unless it is a
                // snapshot plan that a whole turn went by without updating:
                // Codex leaves plans it abandoned half-done, and nothing else
                // clears them.
                if self.is_all_completed() || (self.saw_untouched_turn && self.is_snapshot_list()) {
                    self.items.clear();
                    self.parked_changes.clear();
                    self.clear_undo_journal();
                }
                if !self.turn_open {
                    self.turn_open = true;
                    self.turn_started_at = Some(now);
                    self.touched_this_turn = false;
                    self.saw_untouched_turn = false;
                }
            }
            AgentTaskEvent::TurnEnded => {
                if !self.turn_open {
                    return false;
                }
                self.turn_open = false;
                let lasted = if self.is_replaying {
                    f64::INFINITY
                } else {
                    self.turn_started_at
                        .map_or(0.0, |started| now.0 - started.0)
                };
                if !self.touched_this_turn && lasted >= MIN_UNTOUCHED_TURN_DURATION {
                    self.saw_untouched_turn = true;
                }
                return false;
            }
            AgentTaskEvent::Create {
                op_id,
                title,
                active_form,
            } => self.apply_create(op_id, title, active_form.as_deref()),
            AgentTaskEvent::Created {
                op_id,
                task_id,
                title,
                active_form,
            } => self.apply_created(
                op_id.as_deref(),
                task_id,
                title.as_deref(),
                active_form.as_deref(),
            ),
            AgentTaskEvent::CreatedPerText {
                op_id,
                task_id,
                title,
            } => self.apply_created(Some(op_id), task_id, title.as_deref(), None),
            AgentTaskEvent::Update {
                op_id,
                task_id,
                change,
                expected_from,
            } => self.apply_update(op_id.as_deref(), task_id, change, *expected_from),
            AgentTaskEvent::OpFailed { op_id } => self.apply_failure(op_id),
            AgentTaskEvent::Replace { items, .. } => {
                self.items = items
                    .iter()
                    .take(MAX_ITEMS)
                    .enumerate()
                    .map(|(index, draft)| AgentTaskItem {
                        id: format!("step:{index}"),
                        task_id: draft.row_id.clone(),
                        create_op_id: None,
                        title: clean_title(&draft.title),
                        active_form: draft.active_form.as_deref().map(clean_title),
                        status: draft.status,
                    })
                    .collect();
                self.parked_changes.clear();
                self.clear_undo_journal();
            }
            AgentTaskEvent::Merge { rows, .. } => self.apply_merge(rows),
        }

        let changed = self.items != before;
        // A failing unrelated tool also yields OpFailed; only count what
        // actually concerns the list.
        if !event.is_turn_boundary() && (event.builds_list() || changed) {
            self.touched_this_turn = true;
            self.saw_untouched_turn = false;
        }
        if self.is_all_completed() {
            if self.completed_at.is_none() {
                self.completed_at = Some(now);
            }
        } else {
            self.completed_at = None;
        }
        changed
    }

    /// Apply a subagent's or teammate's checklist events to the parent's list.
    ///
    /// They work through the parent's shared Claude task list, so a TaskUpdate
    /// on a task the parent already shows moves that row (and a failed one is
    /// undone). Anything else a child does — its own creates, updates to its
    /// own tasks, snapshot lists — stays off the parent card.
    pub fn apply_shared_updates(&mut self, events: &[AgentTaskEvent], now: Timestamp) -> bool {
        let mut changed = false;
        for event in events {
            let targets_own_row = match event {
                AgentTaskEvent::Update { task_id, .. } => self
                    .items
                    .iter()
                    .any(|item| item.task_id.as_deref() == Some(task_id.as_str())),
                AgentTaskEvent::OpFailed { op_id } => self.undo_journal.contains_key(op_id),
                _ => false,
            };
            if targets_own_row && self.apply(event, now) {
                changed = true;
            }
        }
        changed
    }

    /// Rebuild a session's list from its transcript on attach.
    ///
    /// - A transcript without checklist-building operations says nothing new:
    ///   keep `live`.
    /// - A scan that covered the whole transcript is authoritative: replay it
    ///   from empty (persisted rows are the same tool calls, replayed).
    /// - A scan of only the transcript's tail cannot see creates older than the
    ///   window, so it replays on top of the live rows instead; per-id merges
    ///   keep that idempotent.
    ///
    /// Replayed completions are stamped the distant past: a list that finished
    /// before the island attached must not flash "all done" on the card.
    pub fn rebuilt(events: &[AgentTaskEvent], covers_whole_transcript: bool, live: Self) -> Self {
        if !events.iter().any(AgentTaskEvent::builds_list) {
            return live;
        }
        let mut board = if covers_whole_transcript {
            Self::new()
        } else {
            Self::restored(live.items.clone(), live.completed_at)
        };
        board.is_replaying = true;
        board.apply_all(events, Timestamp(f64::NEG_INFINITY));
        board.is_replaying = false;
        board
    }

    // MARK: - Operation handlers

    fn apply_create(&mut self, op_id: &str, title: &str, active_form: Option<&str>) {
        let title = clean_title(title);
        let active_form = active_form.map(clean_title);
        if let Some(index) = self
            .items
            .iter()
            .position(|item| item.create_op_id.as_deref() == Some(op_id))
        {
            // Result already landed via the other channel — just fill gaps.
            if self.items[index].active_form.is_none() {
                self.items[index].active_form = active_form;
            }
            if self.items[index].title.is_empty() {
                self.items[index].title = title;
            }
            return;
        }
        if self.items.len() >= MAX_ITEMS {
            return;
        }
        self.items.push(AgentTaskItem {
            id: format!("op:{op_id}"),
            task_id: None,
            create_op_id: Some(op_id.to_owned()),
            title,
            active_form,
            status: AgentTaskStatus::Pending,
        });
    }

    fn apply_created(
        &mut self,
        op_id: Option<&str>,
        task_id: &str,
        title: Option<&str>,
        active_form: Option<&str>,
    ) {
        let title = title.map(clean_title).filter(|title| !title.is_empty());
        let active_form = active_form.map(clean_title);
        let mut index = self
            .items
            .iter()
            .position(|item| item.task_id.as_deref() == Some(task_id));
        if let Some(op_id) = op_id {
            let draft = self.items.iter().position(|item| {
                item.create_op_id.as_deref() == Some(op_id) && item.task_id.is_none()
            });
            if let Some(draft) = draft {
                if index.is_none() {
                    self.items[draft].task_id = Some(task_id.to_owned());
                    index = Some(draft);
                } else {
                    // Both a draft and an id-keyed row exist for one create;
                    // keep the id-keyed row.
                    self.items.remove(draft);
                    index = self
                        .items
                        .iter()
                        .position(|item| item.task_id.as_deref() == Some(task_id));
                }
            }
        }
        if index.is_none() {
            if self.items.len() >= MAX_ITEMS {
                return;
            }
            self.items.push(AgentTaskItem {
                id: format!("task:{task_id}"),
                task_id: Some(task_id.to_owned()),
                create_op_id: op_id.map(str::to_owned),
                title: title.clone().unwrap_or_else(|| format!("#{task_id}")),
                active_form: active_form.clone(),
                status: AgentTaskStatus::Pending,
            });
            index = Some(self.items.len() - 1);
        }
        let Some(index) = index else {
            return;
        };
        if self.items[index].create_op_id.is_none() {
            self.items[index].create_op_id = op_id.map(str::to_owned);
        }
        if let Some(title) = title {
            let placeholder = format!("#{task_id}");
            if self.items[index].title.is_empty() || self.items[index].title == placeholder {
                self.items[index].title = title;
            }
        }
        if self.items[index].active_form.is_none() {
            self.items[index].active_form = active_form;
        }
        if let Some(parked) = self.parked_changes.remove(task_id) {
            self.apply_change(&parked.change, parked.op_id.as_deref(), index);
        }
    }

    fn apply_update(
        &mut self,
        op_id: Option<&str>,
        task_id: &str,
        change: &AgentTaskChange,
        expected_from: Option<AgentTaskStatus>,
    ) {
        let Some(index) = self
            .items
            .iter()
            .position(|item| item.task_id.as_deref() == Some(task_id))
        else {
            // The TaskCreate result is still in flight — park the change until
            // the row exists.
            if let Some(existing) = self.parked_changes.get(task_id) {
                let merged = existing.change.merged_with(change);
                self.parked_changes.insert(
                    task_id.to_owned(),
                    ParkedChange {
                        op_id: op_id.map(str::to_owned).or_else(|| existing.op_id.clone()),
                        change: merged,
                    },
                );
            } else if self.parked_changes.len() < MAX_PARKED_CHANGES {
                self.parked_changes.insert(
                    task_id.to_owned(),
                    ParkedChange {
                        op_id: op_id.map(str::to_owned),
                        change: change.clone(),
                    },
                );
            }
            return;
        };
        // A result whose transition no longer matches lost the race to a newer
        // update; replaying it would roll the status back.
        if let (Some(expected_from), true) =
            (expected_from, change.status.is_some() || change.is_deletion)
        {
            if self.items[index].status != expected_from {
                return;
            }
        }
        self.apply_change(change, op_id, index);
    }

    fn apply_change(&mut self, change: &AgentTaskChange, op_id: Option<&str>, index: usize) {
        let before = self.items[index].clone();
        if change.is_deletion {
            self.items.remove(index);
            if let Some(op_id) = op_id {
                self.journal(
                    op_id,
                    UndoEntry {
                        before,
                        after: None,
                        index,
                    },
                );
            }
            return;
        }
        if let Some(status) = change.status {
            self.items[index].status = status;
        }
        if let Some(title) = change.title.as_deref().map(clean_title) {
            if !title.is_empty() {
                self.items[index].title = title;
            }
        }
        if let Some(active_form) = change.active_form.as_deref().map(clean_title) {
            self.items[index].active_form = Some(active_form);
        }
        if let Some(op_id) = op_id {
            if self.items[index] != before {
                self.journal(
                    op_id,
                    UndoEntry {
                        before,
                        after: Some(self.items[index].clone()),
                        index,
                    },
                );
            }
        }
    }

    fn apply_merge(&mut self, rows: &[AgentTaskRowPatch]) {
        for row in rows {
            if let Some(row_id) = row.row_id.as_deref() {
                if let Some(index) = self
                    .items
                    .iter()
                    .position(|item| item.task_id.as_deref() == Some(row_id))
                {
                    self.apply_change(&row.change, None, index);
                    continue;
                }
            }
            // A row the list doesn't have yet needs at least a title; an
            // `{id, status}` patch for a row we never saw has nothing to show.
            let Some(title) = row.change.title.as_deref().map(clean_title) else {
                continue;
            };
            if row.change.is_deletion || title.is_empty() || self.items.len() >= MAX_ITEMS {
                continue;
            }
            let mut slot = self.items.len();
            while self
                .items
                .iter()
                .any(|item| item.id == format!("step:{slot}"))
            {
                slot += 1;
            }
            self.items.push(AgentTaskItem {
                id: format!("step:{slot}"),
                task_id: row.row_id.clone(),
                create_op_id: None,
                title,
                active_form: row.change.active_form.clone(),
                status: row.change.status.unwrap_or(AgentTaskStatus::Pending),
            });
        }
    }

    fn apply_failure(&mut self, op_id: &str) {
        if let Some(entry) = self.undo_journal.remove(op_id) {
            self.undo_journal_order.retain(|key| key != op_id);
            match &entry.after {
                Some(after) => {
                    // Only undo while the row still shows this op's result — a
                    // newer update since then must not be rolled back with it.
                    if let Some(index) = self.items.iter().position(|item| item.id == after.id) {
                        if self.items[index] == *after {
                            self.items[index] = entry.before;
                        }
                    }
                }
                None => {
                    if !self.items.iter().any(|item| item.id == entry.before.id) {
                        let at = entry.index.min(self.items.len());
                        self.items.insert(at, entry.before);
                    }
                }
            }
            return;
        }
        let draft = self
            .items
            .iter()
            .position(|item| item.create_op_id.as_deref() == Some(op_id) && item.task_id.is_none());
        if let Some(draft) = draft {
            // TaskCreate itself failed: the draft never became a task.
            self.items.remove(draft);
            return;
        }
        let parked = self
            .parked_changes
            .iter()
            .find(|(_, parked)| parked.op_id.as_deref() == Some(op_id))
            .map(|(task_id, _)| task_id.clone());
        if let Some(parked) = parked {
            self.parked_changes.remove(&parked);
        }
    }

    // MARK: - Bookkeeping

    fn record_applied(&mut self, key: String) {
        self.applied_op_keys.push(key.clone());
        self.applied_op_key_set.insert(key);
        let overflow = self
            .applied_op_keys
            .len()
            .saturating_sub(MAX_APPLIED_OP_KEYS);
        if overflow > 0 {
            for evicted in self.applied_op_keys.drain(..overflow) {
                self.applied_op_key_set.remove(&evicted);
            }
        }
    }

    fn journal(&mut self, op_id: &str, entry: UndoEntry) {
        if self.undo_journal.insert(op_id.to_owned(), entry).is_none() {
            self.undo_journal_order.push(op_id.to_owned());
        }
        let overflow = self
            .undo_journal_order
            .len()
            .saturating_sub(MAX_UNDO_ENTRIES);
        if overflow > 0 {
            for evicted in self.undo_journal_order.drain(..overflow) {
                self.undo_journal.remove(&evicted);
            }
        }
    }

    fn clear_undo_journal(&mut self) {
        self.undo_journal.clear();
        self.undo_journal_order.clear();
    }
}

/// Visible state only; bookkeeping differences do not matter to callers.
impl PartialEq for AgentTaskList {
    fn eq(&self, other: &Self) -> bool {
        self.items == other.items && self.completed_at == other.completed_at
    }
}

/// Collapse whitespace and newlines to one line and bound the length — titles
/// come straight from model output.
pub fn clean_title(raw: &str) -> String {
    let collapsed = raw.split_whitespace().collect::<Vec<_>>().join(" ");
    if collapsed.chars().count() <= MAX_TITLE_LENGTH {
        return collapsed;
    }
    let mut trimmed: String = collapsed.chars().take(MAX_TITLE_LENGTH - 1).collect();
    trimmed.push('\u{2026}');
    trimmed
}

// MARK: - Persistence (`AgentTaskList`'s `Codable`)

/// Swift's `JSONEncoder` writes a bare `Date` as seconds since 2001-01-01
/// (`Date.timeIntervalSinceReferenceDate`), and the macOS store holds lists
/// written that way. Persisted `completedAt` therefore keeps that epoch, so one
/// format serves both cores.
const APPLE_REFERENCE_DATE_OFFSET: f64 = 978_307_200.0;

fn status_json(status: AgentTaskStatus) -> Value {
    Value::String(status.raw_value().to_owned())
}

impl AgentTaskItem {
    /// The item's `Codable` shape: camelCase keys, status by raw value.
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("id".into(), json!(self.id));
        if let Some(task_id) = &self.task_id {
            map.insert("taskId".into(), json!(task_id));
        }
        if let Some(create_op_id) = &self.create_op_id {
            map.insert("createOpId".into(), json!(create_op_id));
        }
        map.insert("title".into(), json!(self.title));
        if let Some(active_form) = &self.active_form {
            map.insert("activeForm".into(), json!(active_form));
        }
        map.insert("status".into(), status_json(self.status));
        Value::Object(map)
    }

    /// Reads what [`to_json`](Self::to_json) writes. An unknown status (a
    /// provider's vocabulary leaking into the store) decodes as pending, as
    /// `AgentTaskStatus`'s own `init(from:)` does.
    pub fn from_json(value: &Value) -> Option<Self> {
        let map = value.as_object()?;
        let string = |key: &str| map.get(key).and_then(Value::as_str).map(str::to_owned);
        Some(Self {
            id: string("id")?,
            task_id: string("taskId"),
            create_op_id: string("createOpId"),
            title: string("title").unwrap_or_default(),
            active_form: string("activeForm"),
            status: map
                .get("status")
                .and_then(Value::as_str)
                .map(AgentTaskStatus::from_raw_value)
                .unwrap_or(AgentTaskStatus::Pending),
        })
    }
}

impl AgentTaskList {
    /// Only `items` and `completedAt` are persisted; dedupe and undo
    /// bookkeeping is rebuilt from the transcript on relaunch.
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert(
            "items".into(),
            Value::Array(self.items.iter().map(AgentTaskItem::to_json).collect()),
        );
        if let Some(completed_at) = self.completed_at {
            map.insert(
                "completedAt".into(),
                json!(completed_at.0 - APPLE_REFERENCE_DATE_OFFSET),
            );
        }
        Value::Object(map)
    }

    /// Restores a persisted list, bounded like [`restored`](Self::restored).
    pub fn from_json(value: &Value) -> Self {
        let map = value.as_object();
        let items = map
            .and_then(|map| map.get("items"))
            .and_then(Value::as_array)
            .map(|items| items.iter().filter_map(AgentTaskItem::from_json).collect())
            .unwrap_or_default();
        let completed_at = map
            .and_then(|map| map.get("completedAt"))
            .and_then(Value::as_f64)
            .map(|seconds| Timestamp(seconds + APPLE_REFERENCE_DATE_OFFSET));
        Self::restored(items, completed_at)
    }
}
