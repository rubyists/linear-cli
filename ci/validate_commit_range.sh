#!/usr/bin/env bash

usage() {
    cat <<-EOT
	Validate Conventional Commits subjects in the current branch range.

	Usage:
	  $0

	Environment:
	  BASE_REF          Base branch or ref. Defaults to GITHUB_BASE_REF, then main.
EOT
}

die() {
    printf "ERROR: %s\n\n" "$*" >&2
    usage >&2
    exit 1
}

git_or_die() {
    output=$(git "$@" 2>&1)
    status=$?

    if [ "$status" -ne 0 ]
    then
        printf "%s\n" "$output" >&2
        die "git $* failed"
    fi

    printf "%s" "$output"
}

repo_top=$(git_or_die rev-parse --show-toplevel)
validator="$repo_top/ci/validate_conventional_subject.sh"

[ -x "$validator" ] || die "validator is not executable: $validator"

base_input=${BASE_REF:-${GITHUB_BASE_REF:-main}}

base_ref=

if [[ "$base_input" =~ ^[0-9a-fA-F]{40}$ ]]
then
    # GitHub push events provide the exact pre-push commit. A full checkout
    # already contains it, and using the immutable SHA ensures the newly
    # pushed main commit is validated instead of comparing main to itself.
    base_ref_candidates="$base_input"

    if ! git rev-parse --verify --quiet "$base_input" >/dev/null
    then
        # A shallow GitHub checkout may contain only HEAD. Fetch the precise
        # pre-push SHA here rather than requiring workflow-specific setup.
        git_or_die fetch --no-tags origin "$base_input" >/dev/null
    fi
else
    base_name=${base_input#refs/heads/}
    base_name=${base_name#origin/}

    # Prefer the remote-tracking ref. In particular, a developer pushing
    # directly from local main must compare against origin/main, not against
    # local main (HEAD), or the range would be empty and a bypassed commit-msg
    # hook could slip through pre-push validation.
    base_ref_candidates="origin/$base_name $base_input $base_name"
fi

for candidate in $base_ref_candidates
do
    if git rev-parse --verify --quiet "$candidate" >/dev/null
    then
        base_ref=$candidate
        break
    fi
done

[ -n "$base_ref" ] || {
    if [[ "$base_input" =~ ^[0-9a-fA-F]{40}$ ]]
    then
        # `git fetch origin <sha>` normally makes the object directly
        # addressable. Keep FETCH_HEAD as a fallback for Git servers that do
        # not install an anonymous remote-tracking ref for a SHA request.
        base_ref_candidates="$base_input FETCH_HEAD"
    else
        # Local clones normally already have origin/main (or their configured
        # BASE_REF), so this branch is not taken locally. GitHub Actions'
        # default shallow checkout does not; fetch the missing base from here
        # so callers never need a workflow-level FETCH_BASE_REF switch.
        git_or_die fetch --no-tags origin "$base_name:refs/remotes/origin/$base_name" >/dev/null
        base_ref_candidates="origin/$base_name $base_input $base_name"
    fi

    for candidate in $base_ref_candidates
    do
        if git rev-parse --verify --quiet "$candidate" >/dev/null
        then
            base_ref=$candidate
            break
        fi
    done
}

[ -n "$base_ref" ] || die "unable to resolve commit comparison base"

base_sha=$(git_or_die merge-base HEAD "$base_ref")

validation_status=0

while IFS= read -r -d '' subject
do
    "$validator" --subject "$subject"
    status=$?

    if [ "$status" -ne 0 ]
    then
        validation_status=$status
    fi
done < <(git log -z --format='%s' "$base_sha..HEAD")

exit "$validation_status"
