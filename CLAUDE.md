# Claude Code Guidelines

Read and strictly follow [AGENTS.md](./AGENTS.md).

Key restrictions:
- Never modify `.woodpecker.yaml` or `.github/workflows/`. These are owned exclusively by `@aazhrt`.
- Run `./scripts/ci/verify-local.sh` before committing or pushing changes.
- Multiplatform development: core logic must compile and pass tests locally via `cargo test` before opening PRs.
