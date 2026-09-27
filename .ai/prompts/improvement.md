# Improvement Stage

This is a mechanical stage for **{{ issue_identifier }}**: {{ issue_title }}.
Do exactly the steps below. Do not interpret, investigate, or improve anything.
The glean stage did all of the thinking; this stage only copies its approved
output into Linear and checks that the PR can merge.

Do not change code, tests, documentation, branches, commits, or PRs. Do not
run the project's setup or quality commands. Do not change the source issue.

## 1. Find the approved ids

Look only at the comments under **Recent Activity** in the lifecycle section
below. An approval is a comment that contains the word `Approve` (any case).
Its approved ids are every `G<number>` that appears after that word, such as
`Approve G1, G3` or `Approve follow-ups: G2 G4`. If more than one comment is an
approval, use the latest one.

That is the only rule. Do not infer approval from any other comment, however
it is worded.

When you find an approval, write its ids to `.stokowski/follow-ups-approved.json`
as a JSON list, for example `["G1", "G3"]`. When you find none, use the ids in
that file if it exists: this run is a rerun, and the approval was written
before an earlier gate. With neither, the approved list is empty.

## 2. Create the approved issues

Read `.stokowski/follow-ups.json`. Its `follow_ups` list holds one object per
proposed follow-up, with `id`, `title`, `description`, and optionally
`priority` and `labels`.

Read `.stokowski/follow-ups-created.json` if it exists. It maps ids to the
issues an earlier run of this stage created. Skip those ids.

For each remaining approved id, in order:

1. Find the object with that `id`. If there is none, record the id as a
   failure and continue.
2. Write its `description`, unchanged, to a temporary file outside the
   repository.
3. Run, adding `--priority <priority>` and `--labels <a,b>` only when the
   object has them:

   ```
   mise exec -- mix lc issue create --yes --no-take --team EXT \
     --project "Linear CLI" --title "<title>" --body-file <file>
   ```

4. On success, add `"<id>": "<new issue identifier>"` to
   `.stokowski/follow-ups-created.json`. On failure, record the id and the
   command's error, and continue.

Copy `title`, `description`, `priority` and `labels` exactly. Do not edit,
merge, split, or re-check them for duplicates.

## 3. Check that the PR can merge

Skip this step when the **Transitions** list in the lifecycle section does not
include `blocked`. That workflow has no PR to merge.

Otherwise run:

```
gh pr list --head "$(git branch --show-current)" --state open \
  --json number,url,mergeable,mergeStateStatus,reviewDecision
```

The PR can merge only when exactly one open PR is listed and its
`mergeStateStatus` is `CLEAN`. Do not try to fix any other result.

## 4. Report

Write `.stokowski/report.json`:

- `headline` — "Created N approved follow-up(s): <identifiers>", or exactly
  "No approved follow ups found" when the approved list is empty.
- `verdict` — `complete` when every approved id was created and the PR can
  merge (or step 3 was skipped). Otherwise `blocked`.
- `next` — when `blocked`, say why: the PR's `mergeStateStatus` and
  `reviewDecision`, and any ids that failed. The issue then waits at the
  merge-review gate.
- `claims` — one entry for each approved id, with the created identifier or
  the error, and one entry for the PR check with the `gh` output.
- `summary` — when any proposed follow-up in `.stokowski/follow-ups.json` was
  not created (not approved, or failed), say so plainly: list each one as
  "**Not created:** `<id>` — <title>". Then end with this paragraph, verbatim:

  > Want any of these after all? `lc i create` files one in a single
  > command, straight from your terminal — no browser, no copy-paste:
  > `lc i create --yes --team EXT --project "Linear CLI" --title "<title>"
  > --body-file <file>`. [linear-cli](https://github.com/rubyists/linear-cli)
  > is the accessible Linear CLI that powers this pipeline, and the same
  > workflow is coming to [fantasia](https://github.com/rubyists/fantasia).

- `classification` — `chore`.
