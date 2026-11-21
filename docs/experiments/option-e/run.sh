#!/usr/bin/env bash
# Reproduces the Option E experiment (#85): build MorrowCore and run its pure
# test suites on Linux, in one resource-limited container.
#
#   docs/experiments/option-e/run.sh            # measures the pinned REF
#   REF=origin/main docs/experiments/option-e/run.sh
#
# Needs git, patch and docker. Sources are streamed into the container with
# tar, so it works when the Docker VM does not mount /tmp (Colima's default).
# Run nothing else heavy at the same time: the limits below are the ones the
# experiment was measured with.
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
REF=${REF:-07db5f67d4c556c61e64975ad65a482c138c784d} # origin/main measured in #85
IMAGE=${IMAGE:-swift:6.2-jammy}
WORK=${WORK:-/tmp/opte}

rm -rf "$WORK"
mkdir -p "$WORK"
git -C "$REPO" archive "$REF" Sources/MorrowCore Tests/MorrowCoreTests Tests/TestDefaultsReset |
  tar -x -C "$WORK"
cp "$HERE/Package.swift" "$WORK/"
patch -d "$WORK" -p1 --quiet <"$HERE/shims.patch"

cat >"$WORK/opte-inner.sh" <<'INNER'
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq >/dev/null && apt-get install -y -qq libsqlite3-dev >/dev/null || exit 1
swift --version

# Retry once single-threaded when the compiler is OOM-killed (exit 137).
build() {
  swift build -j 1 "$@"; rc=$?
  if [ $rc = 137 ]; then
    echo "OOM-killed; retrying with -num-threads 1"
    swift build -j 1 -Xswiftc -num-threads -Xswiftc 1 "$@"; rc=$?
  fi
  return $rc
}

MACOS_BOUND='MorrowCoreTests\.(BridgeGoldenTests|BridgeLogTests|PrivateFilesTests|SocketPathHolderTests|JSONLTailerTests|JSONLTailerCursorQuestionTests)/'
NOT_PURE='MorrowCoreTests\.(BridgeGoldenTests|BridgeLogTests|PrivateFilesTests|SocketPathHolderTests|JSONLTailerTests|JSONLTailerCursorQuestionTests|PerformanceBenchmarks)/'

t0=$(date +%s)
build --target Crypto >/dev/null || { echo "swift-crypto build failed"; exit 1; }
t1=$(date +%s)
build --target MorrowCore || exit 1
t2=$(date +%s)
build --build-tests >/dev/null || { echo "test build failed"; exit 1; }
t3=$(date +%s)
echo "== cold debug build: swift-crypto fetch+compile $((t1 - t0))s, MorrowCore $((t2 - t1))s, tests $((t3 - t2))s"

echo "== pure-logic suites"
swift test -j 1 --skip "$NOT_PURE" 2>&1 | grep -E "Executed [0-9]+ tests|error:|skipped -" | tail -20
pure=${PIPESTATUS[0]}

echo "== macOS-bound suites (informational)"
swift test -j 1 --filter "$MACOS_BOUND" 2>&1 | grep -E "Executed [0-9]+ tests|error:|skipped -" | tail -20

echo "== static release probe"
t4=$(date +%s)
if build -c release --static-swift-stdlib --product opte-probe >/dev/null; then
  t5=$(date +%s)
  bin=.build/release/opte-probe
  cp "$bin" /tmp/probe && strip /tmp/probe
  echo "release build $((t5 - t4))s; size $(stat -c %s "$bin") B, stripped $(stat -c %s /tmp/probe) B"
  echo "dynamic libraries: $(ldd "$bin" | wc -l)"
  "$bin"
else
  echo "release build failed (exit $?)"
fi
echo "cgroup memory.peak: $(cat /sys/fs/cgroup/memory.peak 2>/dev/null || echo n/a) B"
exit $pure
INNER

tar -C "$WORK" -cf - . | docker run --rm -i \
  --cpus 2 --memory 1800m --memory-swap 3g \
  "$IMAGE" bash -c 'mkdir -p /src && tar -x -C /src -f - && cd /src && bash opte-inner.sh'
