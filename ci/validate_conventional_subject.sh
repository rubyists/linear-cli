#!/usr/bin/env bash

VALID_TYPES="fix|feat|perf|observability|obs|config|configuration|chore|ci|docs|refactor|sec|security|style|cleanup|test"

allowed_types=$VALID_TYPES
header_pattern="^(${allowed_types})(\\([A-Za-z0-9._/-]+\\))?(!)?: .+"
subject_kind=${CONVENTIONAL_SUBJECT_KIND:-Commit subject}

usage() {
    cat <<-EOT
	Validate a Conventional Commits subject.

	Usage:
	  $0 <commit-message-file>
	  $0 --subject "<subject>"
EOT
}

die() {
    printf "ERROR: %s\n\n" "$*" >&2
    usage >&2
    exit 1
}

if [ "$#" -eq 2 ] && [ "$1" = "--subject" ]
then
    subject=$2
elif [ "$#" -eq 1 ]
then
    message_file=$1
    [ -f "$message_file" ] || die "Commit message file not found: $message_file"

    subject=$(
        sed -n \
            -e '/^[[:space:]]*#/d' \
            -e '/^[[:space:]]*$/d' \
            -e 'p;q' \
            "$message_file"
    )
else
    die "Invalid arguments"
fi

[ -n "${subject:-}" ] || die "$subject_kind is empty"

if [[ "$subject" =~ [[:space:]]$ ]]
then
    die "$subject_kind must not end with whitespace: $subject"
fi

if [[ "$subject" =~ ^Merge\ branch\ .+ ]]
then
    cat >&2 <<-EOT
ERROR: $subject_kind must use Conventional Commits format.

$subject_kind:
  $subject

Recommended fix:
  Reword it with chore: in front of the merge subject:
  chore: $subject
EOT
    exit 1
fi

if [[ ! "$subject" =~ $header_pattern ]]
then
    cat >&2 <<-EOT
ERROR: $subject_kind must use Conventional Commits format.

$subject_kind:
  $subject

Expected:
  <type>[(scope)][!]: <description>

Allowed types:
  ${allowed_types//|/, }

Examples:
  docs: update wallet one-pager
  feat(api): add wallet debit endpoint
  fix(db)!: change ledger migration format
EOT
    exit 1
fi
