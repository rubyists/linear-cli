# linear_cli usage rules

## Conventional Commits

- Format every commit subject as `<type>(<scope>)!: <description>` — `(<scope>)` and `!` (breaking change) are optional.
- Allowed types: `feat`, `fix`, `perf`, `observability`/`obs`, `config`/`configuration`, `chore`, `ci`, `docs`, `refactor`, `sec`/`security`, `style`, `cleanup`, `test`.
- Use the imperative, present tense in the description (`add`, not `added`/`adds`).
- Mark breaking changes with `!` before the colon (e.g. `feat!: ...`).
- Bare `Merge branch ...` subjects are rejected — reword as `chore: Merge branch ...`.
- Enforced locally by the `commit-msg` hook at `githooks/commit-msg`, which
  delegates to `ci/validate_conventional_commit.sh` — run
  `git config core.hooksPath githooks` once per clone to activate it.
- Enforced in CI across a whole PR's commit range by `ci/conventional_commits.sh`
  (same validator, run per-commit; skips GitHub's own auto-generated
  update-branch merge commits).
