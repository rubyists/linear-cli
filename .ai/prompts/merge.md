# Claims Stage

You are following up on any unresolved issues from
the approved PR for **{{ issue_identifier }}**: {{ issue_title }}

**URL:** {{ issue_url }}

## Objective



## Process

1. Find the open PR for this issue:
   ```
   gh pr list --head <branch-name>
   ```
2. Verify the PR is approved and CI is passing:
   ```
   gh pr view <number> --json reviewDecision,statusCheckRollup
   ```
3. If CI is failing, investigate briefly.  If it is a flaky test or transient
   failure, re-run the checks.  If it is a real failure, stop and report
   `blocked`.
4. Merge the approved PR after confirming the required approvals and CI:
   ```
   gh pr merge -sd <number>
   ```
5. Update the Linear workpad with the merge confirmation.

The workflow runner owns the transition to `Done`. Do not move the Linear
issue to a terminal state yourself.

If you did not merge the PR, for any reason — no approval, failing CI, a
conflict you could not resolve — set `"verdict": "blocked"` in
`.stokowski/report.json` and give the reason in `next`. The issue then waits at
the merge-review gate instead of being marked done. Use `complete` only after
the PR is merged.

## Rework run

If this is a rework run (merge was attempted before but failed):

1. Check why the previous merge attempt failed (CI failure, merge conflict, etc.).
2. If there is a merge conflict:
   - Rebase the branch onto `main` and resolve conflicts.
   - Push the updated branch.
   - Wait for CI to pass, then merge.
3. If CI failed:
   - Read the failure logs.
   - If it is a test failure caused by the PR's changes, post details to
     `.stokowski/report.json` and stop with `blocked` (this needs to go back
     to implementation).
   - If it is a flaky or infrastructure issue, re-run and retry the merge.
4. Update the workpad with what happened.

## Do NOT

- Make code changes beyond conflict resolution.
- Open new PRs.
- Skip CI checks.
- Move the source issue to a terminal state.
