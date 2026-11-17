#!/usr/bin/env bash
# Validates commit subjects for every non-deletion ref update received on
# Git's pre-push stdin. Each input line has the format:
#   <local-ref> <local-sha1> <remote-ref> <remote-sha1>
#
# Deletions (local SHA is all zeros) are skipped. For new branches (remote
# SHA is all zeros) the base is the merge base with origin/main or main.
# For existing remote branches the exact remote SHA is used as the base.
#
# Activated automatically by git-hooks/pre-push. May also be invoked
# directly for testing or manual audits with push-ref lines on stdin.

repo_top=$(git rev-parse --show-toplevel) || exit 1
validator="$repo_top/ci/validate_conventional_subject.sh"

if [ ! -x "$validator" ]
then
    printf "ERROR: validator not executable: %s\n" "$validator" >&2
    exit 1
fi

zero_sha="0000000000000000000000000000000000000000"
github_merge_pattern="^Merge branch '[^']+' into .+"
validation_status=0

while read -r local_ref local_sha remote_ref remote_sha
do
    [ "$local_sha" = "$zero_sha" ] && continue

    if [ "$remote_sha" = "$zero_sha" ]
    then
        base_ref=""
        for candidate in origin/main main
        do
            if git rev-parse --verify --quiet "$candidate" >/dev/null
            then
                base_ref=$candidate
                break
            fi
        done

        if [ -z "$base_ref" ]
        then
            printf "ERROR: unable to resolve base ref for new branch %s\n" "$local_ref" >&2
            validation_status=1
            continue
        fi

        base_sha=$(git merge-base "$local_sha" "$base_ref" 2>&1)
        if [ $? -ne 0 ]
        then
            printf "ERROR: git merge-base %s %s failed: %s\n" "$local_sha" "$base_ref" "$base_sha" >&2
            validation_status=1
            continue
        fi
    else
        base_sha="$remote_sha"
    fi

    while IFS= read -r -d '' entry
    do
        IFS=$'\x01' read -r parents committer_name committer_email subject <<< "$entry"

        if [ -n "$parents" ]
        then
            IFS=' ' read -ra parents_array <<< "$parents"
            parent_count=${#parents_array[@]}
        else
            parent_count=0
        fi

        if [ "$parent_count" -eq 2 ] \
            && [ "$committer_name" = "GitHub" ] \
            && [ "$committer_email" = "noreply@github.com" ] \
            && [[ "$subject" =~ $github_merge_pattern ]]
        then
            continue
        fi

        "$validator" --subject "$subject"
        status=$?

        if [ "$status" -ne 0 ]
        then
            validation_status=$status
        fi
    done < <(git log -z --format='%P%x01%cn%x01%ce%x01%s' "$base_sha..$local_sha")
done

exit "$validation_status"
