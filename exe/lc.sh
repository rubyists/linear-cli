#!/usr/bin/env bash
if [ "$#" -eq 0 ]; then
    printf "No subcommand provided, defaulting to 'lc issue list'\nlc --help to see subcommands\n" >&2
    exec linear-cli issue list
fi
if [[ "$*" =~ --help|-h ]]
then
    printf "Each subcommand has its own help, use 'lc <subcommand> --help' to see it\n" >&2
    linear-cli "$@" 2>&1|sed 's/linear-cli/lc/g'
    exit 0
fi
exec linear-cli "$@"
