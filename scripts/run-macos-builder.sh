#!/usr/bin/env bash
set -euo pipefail

# Auto-allow X11 display connection from container
if command -v xhost >/dev/null 2>&1; then
    xhost +local:root >/dev/null 2>&1 || true
    xhost + >/dev/null 2>&1 || true
fi

# Ensure persistent directory exists on host
PERSISTENT_DIR="$HOME/macos-sonoma-data"
mkdir -p "$PERSISTENT_DIR"

# Ensure persistent disk image exists (128GB sparse QCOW2)
if [ ! -f "$PERSISTENT_DIR/mac_hdd_ng.img" ]; then
    echo "==> Initializing persistent macOS disk image at $PERSISTENT_DIR/mac_hdd_ng.img..."
    docker run --rm -v "$PERSISTENT_DIR:/data" sickcodes/docker-osx:latest qemu-img create -f qcow2 /data/mac_hdd_ng.img 128G
fi

# Detect display (default to :0 if empty)
export DISPLAY="${DISPLAY:-:0}"

echo "==> Docker-OSX macOS Sonoma VM Launcher (Persistent Mode)"
echo "==> Disk: $PERSISTENT_DIR/mac_hdd_ng.img (Protected against container deletion)"
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

# If container already exists and is running, attach or inform
if docker ps --format '{{.Names}}' | grep -q "^macos-builder$"; then
    echo "==> Container macos-builder is ALREADY RUNNING."
    echo "==> Attaching or viewing display..."
    exit 0
fi

# If container exists but is stopped, simply restart it (preserve everything)
if docker ps -a --format '{{.Names}}' | grep -q "^macos-builder$"; then
    echo "==> Found existing container 'macos-builder'. Starting it safely..."
    docker start -ai macos-builder
    exit 0
fi

# Otherwise, create container with PERSISTENT DISK MOUNT
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
    -v "$PERSISTENT_DIR/mac_hdd_ng.img:/home/arch/OSX-KVM/mac_hdd_ng.img" \
    -v "$PERSISTENT_DIR:/var/lib/docker-osx" \
    sickcodes/docker-osx:latest
