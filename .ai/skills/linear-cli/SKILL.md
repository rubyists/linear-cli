---
name: linear-cli
description: Create and organize Linear CLI repository issues with mix lc, body-file descriptions, assignment/status setup, and dependency links. Use for Linear work in this repository, not unrelated Linear projects.
---

# Linear CLI issues

Use this skill for Linear issue work in the `linear-cli` repository.

## Required client and body handling

- Interact with Linear only through `mix lc`. Do not use an MCP connector,
  browser, direct API request, or another CLI.
- Always create issues with `--body-file PATH`. Never use
  `--description`, including for a one-line body: the body file preserves
  text verbatim and avoids shell-quoting failures.
- Give every issue a dedicated temporary body file. Write the final body to
  that file, pass it to `mix lc issue create`, and remove it when the create
  operation has finished or is abandoned.

## Issue creation

Before creating issues, establish the requested team, project, assignee,
status, labels, and direct dependency graph. Read existing issues only when
needed to avoid duplicates.

For each issue:

1. Write one independently implementable outcome with a concise title.
2. Put its goal, scope, preserved behavior, exclusions, acceptance criteria,
   and dependencies in the dedicated body file.
3. Create it non-interactively:

   ```sh
   mix lc issue create --yes \
     --team TEAM \
     --project PROJECT \
     --title TITLE \
     --body-file BODY_FILE
   ```

4. Capture the returned identifier. When the user specified an assignee and
   status, apply both explicitly:

   ```sh
   mix lc issue assign --assignee ASSIGNEE --status STATUS ISSUE_ID
   ```

Do not commit while creating or organizing issues unless the user separately
asks for a commit.

## Dependencies

Link a dependent issue to each direct prerequisite:

```sh
mix lc issue relation add DEPENDENT_ID PREREQUISITE_ID --type blocked-by
```

Use only direct edges; do not add relationships implied transitively. Verify
the finished graph with `mix lc issue relation list ISSUE_ID` for every
affected issue, then report the issue identifiers, assignment/status, direct
blockers, and independent work.

## Authorization

This skill standardizes mechanics only. It does not authorize creating,
editing, assigning, or linking Linear issues; obtain the user's request before
performing each external change.
