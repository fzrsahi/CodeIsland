# Claude Code Guidelines

> [!IMPORTANT]
> Read and strictly follow all repository architecture boundaries, restricted zones, and SOP in [AGENTS.md](./AGENTS.md).

Key restrictions & rules:
- **Restricted Zones:** Never modify `.woodpecker.yaml`, `.github/workflows/`, or host runner scripts. These are owned exclusively by `@aazhrt`.
- **Git & PR SOP:** Always ensure an Issue exists before opening a PR (`gh issue create`). Adhere to 1 Issue = 1 PR, and use Stacked PRs for interdependent tasks.
- **Local Verification:** Always run `./scripts/ci/verify-local.sh` before committing or pushing changes.
- **Multiplatform:** Rust core logic must compile and pass tests locally via `cargo test` before opening PRs.
