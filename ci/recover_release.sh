#!/usr/bin/env bash
# Re-runs a release whose run failed. Called by the manage-release-pr job on
# every push to main.
#
# Only the release-PR merge event builds and publishes a release. If that one
# run fails, the manifest version is never tagged, and release-please refuses
# to open any later release PR ("There are untagged, merged release PRs
# outstanding"). This script finds that state and dispatches the release run.
#
# Environment:
#   GH_TOKEN          token for gh; needs actions: write to dispatch
#   RELEASE_WORKFLOW  workflow file to dispatch (default: main.yaml)
#   RELEASE_MANIFEST  release-please manifest (default: .release-please-manifest.json)

workflow="${RELEASE_WORKFLOW:-main.yaml}"
manifest="${RELEASE_MANIFEST:-.release-please-manifest.json}"

if ! version=$(jq -er '."."' "$manifest")
then
    printf 'ERROR: unable to read the version from %s\n' "$manifest" >&2
    exit 1
fi
tag="v$version"

if gh release view "$tag" --json tagName >/dev/null 2>&1
then
    printf 'Release %s exists; nothing to recover\n' "$tag"
    exit 0
fi

# A release-PR merge run (pull_request) or an earlier recovery
# (workflow_dispatch) may still be building this release. Leave it alone; the
# next push to main checks again.
if ! in_flight=$(gh run list --workflow "$workflow" --limit 50 \
    --json event,status \
    --jq '[.[] | select(.status != "completed")
                | select(.event == "pull_request" or .event == "workflow_dispatch")]
           | length')
then
    printf 'ERROR: unable to list %s runs\n' "$workflow" >&2
    exit 1
fi

if [ "$in_flight" != "0" ]
then
    printf 'Release %s is missing, but %s release-capable run(s) are in progress; not dispatching\n' \
        "$tag" "$in_flight"
    exit 0
fi

if ! gh workflow run "$workflow" --ref main
then
    printf 'ERROR: release %s is missing and dispatching %s failed\n' "$tag" "$workflow" >&2
    exit 1
fi

printf '::warning::Release %s was missing; dispatched %s to build and publish it\n' "$tag" "$workflow"
exit 0
