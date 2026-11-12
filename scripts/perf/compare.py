#!/usr/bin/env python3
"""Summarise and compare CodeIsland benchmark runs. Python 3 stdlib only.

  compare.py summarize RUN_DIR
      Reads the raw files bench.sh left in RUN_DIR (top.txt, sample.txt,
      counters-start.json, counters-end.json, memory.json) and writes
      RUN_DIR/result.json.

  compare.py report --baseline FILE --env ENV.json [--update] RUN_DIR...
      Groups runs by scenario (median of repeated runs), prints a table,
      checks targets and regressions against FILE and exits 1 on failure.
      --update writes the medians into FILE instead of failing on them;
      targets and their "enforce" flags are kept.

See CONTRIBUTING.md, "Performance benchmark".
"""

import argparse
import json
import os
import re
import statistics
import sys

SCHEMA = 1

# Regression: value > baseline * RATIO and value - baseline > noise floor.
RATIO = 1.25
NOISE = {
    "cpu": 0.5,                 # percentage points
    "idleWakeupsPerSec": 20.0,
    "footprintEndMB": 5.0,
    "footprintPeakMB": 5.0,
}
COUNTER_NOISE = 2.0             # per minute

# Metrics shown and compared, in order. Report-only metrics have no noise floor.
METRICS = [
    ("cpu", "CPU %"),
    ("idleWakeupsPerSec", "idle wakeups/s"),
    ("power", "Energy Impact (top POWER)"),
    ("mainThreadBusyPct", "main thread busy % (sample)"),
    ("footprintStartMB", "footprint start MB"),
    ("footprintEndMB", "footprint end MB"),
    ("footprintPeakMB", "footprint peak MB"),
    ("footprintGrowthPct", "footprint growth %"),
    ("rssMB", "RSS MB"),
]

DEFAULT_TARGETS = {
    "idle": {
        "cpu": {"max": 2.0, "enforce": False},
        "counters.hostingLayoutPass": {"max": 10.0, "enforce": False},
        "footprintGrowthPct": {"max": 10.0, "enforce": False},
    },
    "idle-prayer": {
        "cpu": {"max": 2.0, "enforce": False},
        "counters.hostingLayoutPass": {"max": 10.0, "enforce": False},
        "footprintGrowthPct": {"max": 10.0, "enforce": False},
    },
    "music": {
        "cpu": {"max": 3.0, "enforce": False},
        "counters.hostingLayoutPass": {"max": 70.0, "enforce": False},
    },
    "waiting-long": {
        "cpu": {"max": 2.0, "enforce": False},
    },
}


# ---------------------------------------------------------------- summarize

def parse_top(path, pid):
    """CPU and POWER per sample (first dropped), wakeups/s from cumulative IDLEW."""
    cpu, power, idlew = [], [], []
    pat = re.compile(r"^\s*%s\s+([\d.]+)\s+(\d+)\S*\s+([\d.]+)" % re.escape(str(pid)))
    with open(path, errors="replace") as f:
        for line in f:
            m = pat.match(line)
            if m:
                cpu.append(float(m.group(1)))
                idlew.append(int(m.group(2)))
                power.append(float(m.group(3)))
    if len(cpu) < 3:
        raise SystemExit("top.txt: fewer than 3 samples for pid %s" % pid)
    seconds = len(idlew) - 1
    return {
        "cpu": round(statistics.mean(cpu[1:]), 2),
        "power": round(statistics.mean(power[1:]), 2),
        "idleWakeupsPerSec": round((idlew[-1] - idlew[0]) / seconds, 1),
        "topSamples": len(cpu) - 1,
    }


LINE = re.compile(r"^([ +!:|]*)(\d+) (.*)$")
IDLE_FRAME = "__CFRunLoopServiceMachPort"


def frame_name(text):
    """'foo(bar)  (in SwiftUI) + 12  [0x..]' -> ('foo(bar)', 'SwiftUI')."""
    m = re.match(r"^(.*?)  \(in ([^)]+)\)", text)
    if m:
        return m.group(1).strip(), m.group(2)
    return text.split("  [")[0].strip(), ""


def parse_sample(path):
    """Main-thread busy % and the five hottest functions.

    Idle is time parked in the outermost run loop's mach_msg wait; time in a
    nested wait (a synchronous XPC call, say) counts as busy.
    """
    with open(path, errors="replace") as f:
        lines = f.read().splitlines()
    start = None
    for i, line in enumerate(lines):
        if "Thread_" in line and "Main Thread" in line:
            start = i
            break
    if start is None:
        return {"mainThreadBusyPct": None, "busyByImage": [], "topCodeIsland": []}
    total = int(LINE.match(lines[start].lstrip()).group(2)) if LINE.match(lines[start].lstrip()) else 0
    base_indent = len(lines[start]) - len(lines[start].lstrip())

    nodes = []  # (depth, count, name, image)
    for line in lines[start + 1:]:
        m = LINE.match(line[base_indent:]) if len(line) > base_indent else None
        if not m or "Thread_" in line:
            break
        depth = len(m.group(1))
        name, image = frame_name(m.group(3))
        nodes.append((depth, int(m.group(2)), name, image))
    if not total:
        return {"mainThreadBusyPct": None, "busyByImage": [], "topCodeIsland": []}

    # Tree from indentation: parent index, own (self) samples, and whether the
    # node sits inside the outermost run-loop wait.
    parents = [None] * len(nodes)
    own = [n[1] for n in nodes]
    stack = []  # (depth, index)
    for idx, (depth, count, _, _) in enumerate(nodes):
        while stack and stack[-1][0] >= depth:
            stack.pop()
        if stack:
            parents[idx] = stack[-1][1]
            own[stack[-1][1]] -= count
        stack.append((depth, idx))

    idle = 0
    in_idle = [False] * len(nodes)
    seen_wait = [False] * len(nodes)  # a wait frame at or above this node
    ancestor_names = [frozenset()] * len(nodes)
    for idx, (_, count, name, _) in enumerate(nodes):
        p = parents[idx]
        above = seen_wait[p] if p is not None else False
        ancestor_names[idx] = (ancestor_names[p] | {nodes[p][2]}) if p is not None else frozenset()
        if name == IDLE_FRAME and not above:
            idle += count
            in_idle[idx] = True
        elif p is not None and in_idle[p]:
            in_idle[idx] = True
        seen_wait[idx] = above or name == IDLE_FRAME

    by_image, inclusive = {}, {}
    for idx, (_, count, name, image) in enumerate(nodes):
        if own[idx] > 0 and not in_idle[idx]:
            key = image or "?"
            by_image[key] = by_image.get(key, 0) + own[idx]
        # Inclusive time, counted once per recursion chain.
        if image == "CodeIsland" and name not in ancestor_names[idx] and not name.startswith("CodeIsland_main"):
            inclusive[name] = inclusive.get(name, 0) + count

    def top(d, label):
        return [
            {label: k, "pct": round(100.0 * v / total, 1)}
            for k, v in sorted(d.items(), key=lambda kv: -kv[1])[:5]
        ]

    return {
        "mainThreadBusyPct": round(100.0 * (total - idle) / total, 1),
        "busyByImage": top(by_image, "image"),
        "topCodeIsland": top(inclusive, "function"),
    }


def counter_rates(start_path, end_path):
    with open(start_path) as f:
        a = json.load(f)
    with open(end_path) as f:
        b = json.load(f)
    minutes = (b["uptimeSeconds"] - a["uptimeSeconds"]) / 60.0
    if minutes <= 0:
        raise SystemExit("counter snapshots are not ordered in time")
    keys = set(a["counters"]) | set(b["counters"])
    return {
        k: round((b["counters"].get(k, 0) - a["counters"].get(k, 0)) / minutes, 1)
        for k in sorted(keys)
    }


def summarize(run_dir):
    with open(os.path.join(run_dir, "run.json")) as f:
        run = json.load(f)
    with open(os.path.join(run_dir, "memory.json")) as f:
        mem = json.load(f)
    result = {"scenario": run["scenario"], "pid": run["pid"]}
    result.update(parse_top(os.path.join(run_dir, "top.txt"), run["pid"]))
    sample = parse_sample(os.path.join(run_dir, "sample.txt"))
    result["mainThreadBusyPct"] = sample["mainThreadBusyPct"]
    result["busyByImage"] = sample["busyByImage"]
    result["topCodeIsland"] = sample["topCodeIsland"]
    result["footprintStartMB"] = mem["footprintStartMB"]
    result["footprintEndMB"] = mem["footprintEndMB"]
    result["footprintPeakMB"] = mem["footprintPeakMB"]
    result["footprintGrowthPct"] = round(
        100.0 * (mem["footprintEndMB"] - mem["footprintStartMB"]) / mem["footprintStartMB"], 1
    )
    result["rssMB"] = mem["rssMB"]
    result["counters"] = counter_rates(
        os.path.join(run_dir, "counters-start.json"), os.path.join(run_dir, "counters-end.json")
    )
    with open(os.path.join(run_dir, "result.json"), "w") as f:
        json.dump(result, f, indent=2, sort_keys=True)
    return result


# ------------------------------------------------------------------- report

def median_runs(runs):
    """Median per numeric metric and per counter; hot functions from the median-CPU run."""
    out = {"runs": len(runs)}
    for key, _ in METRICS:
        vals = [r[key] for r in runs if r.get(key) is not None]
        out[key] = round(statistics.median(vals), 2) if vals else None
    counters = sorted({k for r in runs for k in r["counters"]})
    out["counters"] = {
        k: round(statistics.median([r["counters"].get(k, 0.0) for r in runs]), 1) for k in counters
    }
    mid = sorted(runs, key=lambda r: r["cpu"])[len(runs) // 2]
    out["busyByImage"] = mid.get("busyByImage", [])
    out["topCodeIsland"] = mid.get("topCodeIsland", [])
    return out


def lookup(m, key):
    if key.startswith("counters."):
        return m.get("counters", {}).get(key[len("counters."):], 0.0)
    return m.get(key)


def is_regression(key, value, base):
    if value is None or base is None:
        return False
    if key.startswith("counters."):
        noise = COUNTER_NOISE
    elif key in NOISE:
        noise = NOISE[key]
    else:
        return False
    return value > base * RATIO and value - base > noise


def fmt(v):
    if v is None:
        return "-"
    if isinstance(v, float):
        return ("%.2f" % v).rstrip("0").rstrip(".") if abs(v) < 1000 else "%.0f" % v
    return str(v)


def env_mismatch(env, base_env):
    reasons = []
    for key, label in (("macModel", "Mac model"), ("macOS", "macOS"), ("players", "running players/browsers")):
        if base_env.get(key) != env.get(key):
            reasons.append("%s %s ≠ baseline %s" % (label, env.get(key), base_env.get(key)))
    return reasons


def report(args):
    runs = []
    for d in args.run_dirs:
        with open(os.path.join(d, "result.json")) as f:
            runs.append(json.load(f))
    with open(args.env) as f:
        env = json.load(f)

    baseline = None
    if os.path.exists(args.baseline):
        with open(args.baseline) as f:
            baseline = json.load(f)
    targets = (baseline or {}).get("targets", DEFAULT_TARGETS)

    by_scenario = {}
    for r in runs:
        by_scenario.setdefault(r["scenario"], []).append(r)
    medians = {s: median_runs(rs) for s, rs in by_scenario.items()}

    compare_regressions = baseline is not None and not args.update
    if compare_regressions:
        reasons = env_mismatch(env, baseline.get("environment", {}))
        if reasons:
            print("⚠️  Environment differs from baseline (%s): regressions skipped, targets only." % "; ".join(reasons))
            compare_regressions = False

    failures = []
    for scenario, m in medians.items():
        base = ((baseline or {}).get("scenarios", {}) or {}).get(scenario) if compare_regressions else None
        print("\n== %s (%d run%s) ==" % (scenario, m["runs"], "" if m["runs"] == 1 else "s"))
        print("%-34s %10s %10s  %s" % ("metric", "value", "baseline", "status"))
        rows = [(k, label) for k, label in METRICS] + [
            ("counters." + k, "%s /min" % k) for k in m["counters"]
        ]
        if base:
            for k in base.get("counters", {}):
                if k not in m["counters"]:
                    rows.append(("counters." + k, "%s /min" % k))
        scenario_targets = targets.get(scenario, {})
        for key, label in rows:
            value = lookup(m, key)
            bval = lookup(base, key) if base else None
            status = []
            if base and is_regression(key, value, bval):
                status.append("✗ regression")
                failures.append("%s: %s %s > baseline %s" % (scenario, label, fmt(value), fmt(bval)))
            t = scenario_targets.get(key)
            if t is not None and value is not None:
                ok = value <= t["max"]
                status.append("%s target ≤ %s%s" % ("✓" if ok else "✗", fmt(t["max"]), "" if t.get("enforce") else " (not enforced)"))
                if not ok and t.get("enforce"):
                    failures.append("%s: %s %s > target %s" % (scenario, label, fmt(value), fmt(t["max"])))
            print("%-34s %10s %10s  %s" % (label, fmt(value), fmt(bval), ", ".join(status)))
        for title, key, field in (
            ("main thread busy time by image (self)", "busyByImage", "image"),
            ("hottest CodeIsland functions, main thread (inclusive)", "topCodeIsland", "function"),
        ):
            if m.get(key):
                print("  %s:" % title)
                for fn in m[key]:
                    print("    %5.1f%%  %s" % (fn["pct"], fn[field][:110]))

    if args.update:
        new = baseline or {}
        new["schema"] = SCHEMA
        new["environment"] = env
        new["targets"] = targets
        scenarios = new.get("scenarios", {})
        scenarios.update(medians)
        new["scenarios"] = scenarios
        with open(args.baseline, "w") as f:
            json.dump(new, f, indent=2, sort_keys=True, ensure_ascii=False)
            f.write("\n")
        print("\nBaseline written: %s" % args.baseline)
        return 0

    if baseline is None:
        print("\nNo baseline at %s: run with --update-baseline to record one." % args.baseline)
    if failures:
        print("\nFAIL")
        for line in failures:
            print("  " + line)
        return 1
    print("\nPASS")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("summarize")
    s.add_argument("run_dir")
    r = sub.add_parser("report")
    r.add_argument("--baseline", required=True)
    r.add_argument("--env", required=True)
    r.add_argument("--update", action="store_true")
    r.add_argument("run_dirs", nargs="+")
    args = p.parse_args()
    if args.cmd == "summarize":
        summarize(args.run_dir)
        return 0
    return report(args)


if __name__ == "__main__":
    sys.exit(main())
