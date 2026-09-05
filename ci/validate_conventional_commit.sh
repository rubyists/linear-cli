#!/usr/bin/env bash
# Compatibility wrapper — the implementation has moved to git-hooks/validate-conventional-subject.
script_dir=$(cd "$(dirname "$0")" && pwd)
exec "$script_dir/../git-hooks/validate-conventional-subject" "$@"
