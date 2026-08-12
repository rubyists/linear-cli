#!/usr/bin/env bash
# Removes exactly what install.sh installed, using the manifest it wrote -
# not a guess at where things might be, so this stays correct even if
# $PATH changed since install.

state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/linear-cli"
manifest="$state_dir/manifest"

if [ ! -f "$manifest" ]
then
    printf 'error: no manifest at %s - nothing to uninstall (or it was installed another way, e.g. Homebrew: use `brew uninstall lc` instead)\n' "$manifest" >&2
    exit 1
fi

removed=0
failed=0
while IFS= read -r path
do
    [ -n "$path" ] || continue

    if [ -e "$path" ]
    then
        if rm -f "$path"
        then
            printf 'removed %s\n' "$path"
            removed=$((removed + 1))
        else
            printf 'error: failed to remove %s\n' "$path" >&2
            failed=$((failed + 1))
        fi
    fi
done < "$manifest"

rm -f "$manifest"
rmdir "$state_dir" 2>/dev/null

if [ "$failed" -ne 0 ]
then
    printf '%d file(s) removed, %d failed\n' "$removed" "$failed" >&2
    exit 1
fi

printf '%d file(s) removed\n' "$removed"
