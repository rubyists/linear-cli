# linear_cli usage rules

## Conventional Commits

- Format every commit subject as `<type>(<scope>)!: <description>` — `(<scope>)` and `!` (breaking change) are optional.
- Allowed types: `feat`, `fix`, `perf`, `observability`/`obs`, `config`/`configuration`, `chore`, `ci`, `docs`, `refactor`, `sec`/`security`, `style`, `cleanup`, `test`.
- Use the imperative, present tense in the description (`add`, not `added`/`adds`).
- Mark breaking changes with `!` before the colon (e.g. `feat!: ...`).
- Bare `Merge branch ...` subjects are rejected — reword as `chore: Merge branch ...`.
- Enforced locally by the `commit-msg` hook at `githooks/commit-msg` (each
  commit's own subject, via `ci/validate_conventional_commit.sh`) and the
  `pre-push` hook at `githooks/pre-push` (every commit about to be pushed,
  via `ci/conventional_commits.sh` - catches anything that slipped past
  `commit-msg`, e.g. a commit made before the hooks were installed) — run
  `mix setup` once per clone to activate both.
- Enforced in CI across a whole PR's commit range by the same
  `ci/conventional_commits.sh` the `pre-push` hook uses (skips GitHub's own
  auto-generated update-branch merge commits).
