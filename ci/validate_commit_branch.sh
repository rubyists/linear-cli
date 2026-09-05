#!/usr/bin/env bash
# Rejects ordinary commits made directly on main. Called by git-hooks/pre-commit
# so the failure occurs before Git creates the commit object.

if ! branch=$(git branch --show-current)
then
    printf 'ERROR: unable to determine the current Git branch\n' >&2
    exit 1
fi

if [ "$branch" = "main" ]
then
    printf 'ERROR: committing directly to main is not allowed; create a feature branch instead\n' >&2
    exit 1
fi
