#!/usr/bin/env bash

usage() {
    cat <<-EOT
    Validate conventional commit subjects in the current branch range.

    Usage:
      $0

    Environment:
      BASE_REF          Base branch or ref. Defaults to GITHUB_BASE_REF, main, then origin/main.
      HEAD_REF          Head branch name. Defaults to GITHUB_HEAD_REF, then current branch.
      FETCH_BASE_REF    When "true", fetch BASE_REF from origin before validating.
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
validator="$repo_top/ci/validate_conventional_commit.sh"

[ -x "$validator" ] || die "validator is not executable: $validator"

base_input=${BASE_REF:-${GITHUB_BASE_REF:-}}
head_branch=${HEAD_REF:-${GITHUB_HEAD_REF:-}}
base_name=${base_input#refs/heads/}
base_name=${base_name#origin/}

if [ -z "$head_branch" ]
then
    head_branch=$(git branch --show-current 2>/dev/null)
fi

if [ "${FETCH_BASE_REF:-}" = "true" ] && [ -n "$base_input" ]
then
    git_or_die fetch --no-tags origin "$base_name:refs/remotes/origin/$base_name" >/dev/null
fi

base_ref=

if [ -n "$base_input" ]
then
    base_ref_candidates="$base_input origin/$base_name $base_name"
else
    base_ref_candidates="main origin/main"
fi

for candidate in $base_ref_candidates
do
    if git rev-parse --verify --quiet "$candidate" >/dev/null
    then
        base_ref=$candidate
        break
    fi
done

[ -n "$base_ref" ] || die "unable to resolve commit comparison base"

base_branch=${base_name:-$base_ref}
base_branch=${base_branch#refs/heads/}
base_branch=${base_branch#origin/}
expected_update_branch_subject="Merge branch '$base_branch' into $head_branch"
base_sha=$(git_or_die merge-base HEAD "$base_ref")

validation_status=0

while IFS= read -r -d '' sha &&
    IFS= read -r -d '' parents &&
    IFS= read -r -d '' committer_name &&
    IFS= read -r -d '' committer_email &&
    IFS= read -r -d '' subject
do
    parent_count=$(printf "%s\n" "$parents" | wc -w | tr -d ' ')

    if [ "$parent_count" = "2" ] &&
        [ "$committer_name" = "GitHub" ] &&
        [ "$committer_email" = "noreply@github.com" ] &&
        [ -n "$head_branch" ] &&
        [ "$subject" = "$expected_update_branch_subject" ]
    then
        printf "Skipping GitHub update-branch merge commit: %s %s\n" "$sha" "$subject" >&2
        continue
    fi

    "$validator" --subject "$subject"
    status=$?

    if [ "$status" -ne 0 ]
    then
        validation_status=$status
    fi
done < <(git log --format='%H%x00%P%x00%cN%x00%cE%x00%s%x00' "$base_sha..HEAD")

exit "$validation_status"
