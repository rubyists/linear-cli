#!/usr/bin/env bash
# Runs Hex's dependency security audit from the app Mix project. This is used
# by the pre-push hook as well as the CI quality gate.

if ! repo_top=$(git rev-parse --show-toplevel 2>&1)
then
    printf 'ERROR: unable to resolve repository root: %s\n' "$repo_top" >&2
    exit 1
fi

app_dir="$repo_top/app"

if [ ! -d "$app_dir" ]
then
    printf 'ERROR: app Mix project not found: %s\n' "$app_dir" >&2
    exit 1
fi

if ! cd "$app_dir"
then
    printf 'ERROR: unable to change to app Mix project: %s\n' "$app_dir" >&2
    exit 1
fi

if ! command -v mix >/dev/null 2>&1
then
    printf 'ERROR: mix is not available on PATH\n' >&2
    exit 1
fi

exec mix hex.audit
