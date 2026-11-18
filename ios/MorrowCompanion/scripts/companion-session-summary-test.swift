import Foundation

// Behavior check for #330: the compact Dynamic Island must change when one of
// several sessions finishes. Runs the real CompanionDisplayText.swift.

func check(_ name: String, _ condition: Bool) {
    print("\(condition ? "PASS" : "FAIL"): \(name)")
    if !condition { exit(1) }
}

// The reported case: three sessions, one finishes. The total is still 3 until
// the Mac retires the session, so the ratio is what has to move.
let before = ["processing", "running", "processing"]
let after = ["processing", "running", "idle"]
check("ratio moves when a session goes idle",
      CompanionSessionSummary.activityRatio(statuses: before) == "3/3"
      && CompanionSessionSummary.activityRatio(statuses: after) == "2/3")

check("active count ignores idle sessions",
      CompanionSessionSummary.activeCount(statuses: after) == 2)

// An approval waiting in a session that is not the featured one used to be
// invisible in the compact view.
check("approval outranks everything",
      CompanionSessionSummary.aggregateStatus(
        statuses: ["running", "waitingApproval", "processing"]) == "waitingApproval")

check("question outranks work but not approval",
      CompanionSessionSummary.aggregateStatus(
        statuses: ["running", "waitingQuestion"]) == "waitingQuestion"
      && CompanionSessionSummary.aggregateStatus(
        statuses: ["waitingApproval", "waitingQuestion"]) == "waitingApproval")

check("processing outranks running",
      CompanionSessionSummary.aggregateStatus(
        statuses: ["running", "processing"]) == "processing")

check("all idle stays idle",
      CompanionSessionSummary.aggregateStatus(statuses: ["idle", "idle"]) == "idle")

// A status from a newer Mac build must not read as active-but-unknown noise in
// the dot; it still counts as active, which is the conservative choice.
check("unknown status is active but not prioritised",
      CompanionSessionSummary.aggregateStatus(statuses: ["compacting"]) == "idle"
      && CompanionSessionSummary.activeCount(statuses: ["compacting"]) == 1)

check("no sessions is a 0/0 ratio, not a crash",
      CompanionSessionSummary.activityRatio(statuses: []) == "0/0")

print("all companion session summary checks passed")
