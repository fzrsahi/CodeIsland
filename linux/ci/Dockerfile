# The Linux X11 desktop image: builds and tests `morrow-app` (Tauri v2 on
# WebKitGTK) and runs linux/ci/smoke-x11.sh under Xvfb with Openbox.
#
#   docker build --memory 1800m -t morrow-tauri-x11:dev -f linux/ci/Dockerfile linux/ci
#
# No node toolchain: the frontend is built beforehand (bun or npm in
# shared/desktop) and Tauri embeds the prebuilt shared/desktop/dist.
FROM rust:1.98-bookworm

# Tauri's GTK3 / WebKitGTK 4.1 build dependencies, then the smoke's X11
# tools: Xvfb, Openbox (an EWMH window manager, so _NET_WM_STATE and
# _NET_ACTIVE_WINDOW mean what they mean on a desktop), xdotool, xprop/xev
# (x11-utils), wmctrl.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev librsvg2-dev \
      xvfb xauth openbox xdotool x11-utils wmctrl procps \
 && rm -rf /var/lib/apt/lists/*

# rust-toolchain.toml pins 1.98.0; the base image ships 1.98.x. Install the
# pinned one now so a run does not download it.
RUN rustup toolchain install 1.98.0 --profile minimal --component rustfmt,clippy \
 && rustup default 1.98.0

WORKDIR /work
