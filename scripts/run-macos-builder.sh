#!/usr/bin/env bash
set -euo pipefail

# Auto-allow X11 display connection from container
if command -v xhost >/dev/null 2>&1; then
    xhost +local:root >/dev/null 2>&1 || true
    xhost + >/dev/null 2>&1 || true
fi

# Detect display (default to :0 if empty)
export DISPLAY="${DISPLAY:-:0}"

# Remove any previous failed container
docker rm -f macos-builder 2>/dev/null || true

# Ensure persistent directory exists on host
mkdir -p "$HOME/macos-sonoma-data"

echo "==> Starting Docker-OSX macOS Sonoma VM with tuned memory (4GB RAM, 4 Cores)..."
echo "==> Display: $DISPLAY"
echo "==> IMPORTANT TIP: DO NOT toggle Fullscreen (Ctrl+Alt+F) to prevent Wayland freezes."
echo "==> To release mouse focus from VM window, press: Ctrl + Alt + G"

# Mount Xauthority if available to guarantee GUI access
XAUTH_ARGS=()
if [ -n "${XAUTHORITY:-}" ] && [ -f "${XAUTHORITY}" ]; then
    XAUTH_ARGS=(-v "${XAUTHORITY}:/home/arch/.Xauthority:ro" -v "${XAUTHORITY}:/root/.Xauthority:ro")
elif [ -f "$HOME/.Xauthority" ]; then
    XAUTH_ARGS=(-v "$HOME/.Xauthority:/home/arch/.Xauthority:ro" -v "$HOME/.Xauthority:/root/.Xauthority:ro")
fi

docker run -it \
    --name macos-builder \
    --device /dev/kvm \
    -p 50922:10022 \
    -v /tmp/.X11-unix:/tmp/.X11-unix \
    "${XAUTH_ARGS[@]}" \
    -e DISPLAY="$DISPLAY" \
    -e GENERATE_UNIQUE=true \
    -e CPU='Haswell-noTSX' \
    -e CPUID_FLAGS='kvm=on,vendor=GenuineIntel,+invtsc,vmware-cpuid-freq=on' \
    -e SHORTNAME=sonoma \
    -e RAM=4 \
    -e SMP=4 \
    -e CORES=4 \
    -v "$HOME/macos-sonoma-data:/var/lib/docker-osx" \
    sickcodes/docker-osx:latest
