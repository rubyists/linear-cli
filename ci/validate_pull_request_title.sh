#!/usr/bin/env bash

required=${PULL_REQUEST_TITLE_REQUIRED:-false}

case "$required" in
    true)
        ;;
    false)
        printf 'Skipping pull request title validation outside a pull request event.\n'
        exit 0
        ;;
    *)
        printf 'ERROR: PULL_REQUEST_TITLE_REQUIRED must be "true" or "false", got: %s\n' "$required" >&2
        exit 1
        ;;
esac

if [ -z "${PULL_REQUEST_TITLE+x}" ]
then
    printf 'ERROR: PULL_REQUEST_TITLE must be set for a pull request event.\n' >&2
    exit 1
fi

repo_top=$(git rev-parse --show-toplevel) || exit 1
validator="$repo_top/ci/validate_conventional_subject.sh"

if [ ! -x "$validator" ]
then
    printf 'ERROR: validator is not executable: %s\n' "$validator" >&2
    exit 1
fi

CONVENTIONAL_SUBJECT_KIND="Pull request title" \
    "$validator" --subject "$PULL_REQUEST_TITLE" || exit $?

printf 'Pull request title uses Conventional Commits format: %s\n' "$PULL_REQUEST_TITLE"
