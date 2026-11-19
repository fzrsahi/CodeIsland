# linux/

Linux packaging and the Linux-only CI scripts: `.deb`, `.rpm` and `.AppImage` builds, the `.desktop` entry, and `linux/ci/test.sh` / `linux/ci/package.sh` once they exist. The Linux app has no shell code of its own here: it is the shared Tauri app in `shared/desktop/` with the Linux backends selected by `#[cfg]` in `morrow-platform` (see `docs/plan-windows-linux.md` §4).
