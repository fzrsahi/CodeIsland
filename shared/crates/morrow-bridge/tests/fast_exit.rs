//! With no island listening the bridge must cost the agent nothing: exit 0
//! in under 10 ms, median of 25 runs (#89). Measured with the binary cargo
//! built for this test; `cargo test --release` (or
//! `MORROW_BRIDGE_UNDER_TEST`) measures the release build. Prints the
//! timings with `--nocapture`.
#![cfg(unix)]

mod common;

use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

use common::{TestDir, bridge_binary};

const RUNS: usize = 25;
const MEDIAN_LIMIT: Duration = Duration::from_millis(10);

#[test]
fn exits_0_in_under_10_ms_without_a_listener() {
    let dir = TestDir::new();
    let socket = dir.join("absent.sock");
    let binary = bridge_binary();
    let mut times: Vec<Duration> = (0..RUNS)
        .map(|_| {
            let started = Instant::now();
            let status = Command::new(&binary)
                .env_clear()
                .env("MORROW_SOCKET_PATH", &socket)
                .stdin(Stdio::piped())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .expect("spawn bridge");
            let elapsed = started.elapsed();
            assert_eq!(status.code(), Some(0));
            elapsed
        })
        .collect();
    times.sort();
    let ms = |d: Duration| d.as_secs_f64() * 1000.0;
    let median = times[RUNS / 2];
    let p95 = times[(RUNS * 95).div_ceil(100) - 1];
    println!(
        "fast exit, {RUNS} runs of {binary}: min {:.2} ms, median {:.2} ms, p95 {:.2} ms, max {:.2} ms",
        ms(times[0]),
        ms(median),
        ms(p95),
        ms(times[RUNS - 1]),
    );
    assert!(median < MEDIAN_LIMIT, "median {:.2} ms", ms(median));
}
