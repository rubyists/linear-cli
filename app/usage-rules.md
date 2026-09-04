# linear_cli usage rules

## Conventional Commits

- Format every commit subject as `<type>(<scope>)!: <description>` — `(<scope>)` and `!` (breaking change) are optional.
- Allowed types: `feat`, `fix`, `perf`, `observability`/`obs`, `config`/`configuration`, `chore`, `ci`, `docs`, `refactor`, `sec`/`security`, `style`, `cleanup`, `test`.
- Use the imperative, present tense in the description (`add`, not `added`/`adds`).
- Mark breaking changes with `!` before the colon (e.g. `feat!: ...`).
- Bare `Merge branch ...` subjects are rejected — reword as `chore: Merge branch ...`.
- Enforced locally by the `commit-msg` hook at `git-hooks/commit-msg` (each
  commit's own subject, via its shared subject validator) and the `pre-push`
  hook at `git-hooks/pre-push` (`mix precommit`, which validates
  every commit about to be pushed and runs the dependency security audits,
  formatting, static analysis, and tests) — run `mix setup` once per clone
  to activate both.
- Enforced in CI across a whole PR's commit range by
  `ci/conventional_commits.sh` (skips GitHub's own auto-generated
  update-branch merge commits).

## Dogfooding: use `lc`, not a Linear MCP server or skill

- When working in this repo, read or write Linear data through this
  repo's own `lc` CLI — never a Linear MCP server or other
  Linear-integration skill. `lc` is the codebase under development;
  routing around it means it never gets exercised.
- There's no escript build (removed - NIF-backed deps like `exqlite`
  can't load from inside an escript archive, so it never actually
  worked once `exqlite` was added). Without a full `mix release lc`
  build, invoke the development checkout from the repo root through its
  proxy task:

      mix lc issue list

  `mix lc` compiles and starts the `app/` project as needed, forwards all
  arguments and standard streams to `LinearCli.CLI.main/1` (including
  interactive prompt input), and preserves its exit code. It also suppresses
  child Mix progress messages so `--output json` stays machine-readable.

## Accessibility

- This project exists so its author can keep using Linear from a terminal
  and a screen reader after losing sight entirely — see
  `documents/motivation.adoc` for why. Every design/review decision here
  weighs accessibility accordingly, not as a nice-to-have.
- Plain, linear text output is first-class: every command's normal output
  must read correctly top-to-bottom through a screen reader, with no
  reliance on spatial layout or color to convey meaning.
- Never encode meaning in color alone (success/failure, warnings, which
  field is which) — color may only decorate a signal that's also present
  in the text itself.
- No TUI as the primary interface for anything `lc` does — full-screen,
  redraw-based UIs fight screen readers. If one's ever added, it must be
  optional, never required.
- Interactive prompts stay line-based (readline-style) — nothing that
  repaints the screen, uses cursor-position tricks, or expects visually
  tracking a moving selection.
- `--output json` stays a fully-supported second path for every command,
  not just a scripting afterthought.
