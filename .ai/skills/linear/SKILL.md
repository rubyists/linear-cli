---
name: linear-cli
description: Create, update, organize, and comment on Linear issues with the Linear CLI. Use when a workflow needs Linear issue work through `lc` rather than a browser or direct API calls.
---

# Linear CLI issues

Use this skill for Linear issue work through the Linear CLI, whether it is
installed on the machine or vendored in the current project.

## Choose the CLI command

First check whether `mise` is available with `mise --version`.

When it is available, always invoke the CLI through `mise x --` so it uses
the configured tool versions. Prefer `mise x -- mix lc`; check with
`mise x -- mix lc --help` from the working directory before the first
operation:

- If the command succeeds, use `mise x -- mix lc` so a vendored or
  project-provided CLI is exercised.
- If it is unavailable, use `mise x -- lc`.

> [!WARNING]
> If `mise` is unavailable, running without it may use different tool
> versions. Use this fallback at your own peril.

Without `mise`, prefer `mix lc` when `mix lc --help` succeeds; otherwise use
the installed `lc` command.

Do not fall back from a failed mutating `mix lc` command to `lc`, whether or
not it runs through `mise`: report that failure instead. The availability
check should happen before an external change.

Before an unfamiliar operation, read the selected command's help, for example
`mise x -- mix lc issue --help` or `mise x -- lc issue create --help`. Without
`mise`, use the equivalent `mix lc` or `lc` command. Do not substitute a
browser, MCP connector, direct API request, or another CLI.

## Body files

Use `--body-file PATH` for issue descriptions and comments whenever the
command supports it. A body file preserves the requested text and avoids
shell-quoting problems. Use a separate temporary file for each create,
description update, or comment, and remove it after the operation succeeds
or is abandoned.

## Issue creation

Before creating issues, establish only the requested team, project, assignee,
status, labels, and direct dependencies. Check for existing issues when that
would help avoid a duplicate.

Each issue should have one independently implementable outcome and a concise
title. Its description should cover the goal, scope, acceptance criteria, and
relevant dependencies or exclusions.

Use non-interactive flags when available and when they match the user's
request. Capture the returned issue identifier, then apply only the requested
assignment, status, labels, project, or relations. Do not infer ownership,
workflow state, or project placement.

Do not commit while creating or organizing issues unless the user separately
asks for a commit.

## Issue updates

Read an issue first when its current state affects the requested change. Make
only the requested update; do not use an update to alter unrelated fields.

## Comments

For comments, state the outcome, useful evidence, and any remaining blocker
or handoff. Avoid restating the full issue description.

## Dependencies

Link each dependent issue to its direct prerequisites using the CLI's
dependency or relation command. Do not add transitive relationships. Verify
the affected relationships when the CLI supports listing them, then report
the issue identifiers, requested state changes, and direct blockers.

## Authorization

This skill standardizes mechanics only. It does not authorize creating,
editing, commenting on, assigning, or linking Linear issues; obtain the user's
request before performing each external change.
