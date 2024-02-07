#!/usr/bin/env bash
if [ "$#" -eq 0 ]; then
    printf "No subcommand provided, defaulting to 'lc issue list'\nlc --help to see subcommands\n" >&2
    exec linear-cli issue list
fi
if [[ "$*" =~ --version ]]
then
    exec linear-cli version
fi
if [[ "$*" =~ --help|-h ]]
then
    output="$(linear-cli "$@" 2>&1|sed 's/linear-cli/lc/g')"
    if [[ "$output" =~ ^Command: ]]
    then
      printf "%s\n" "$output"
    else
      printf "Each subcommand has its own help, use 'lc <subcommand> --help' to see them\n" >&2
      printf "%s\n" "$output"
    fi
    exit 0
fi
linear-cli "$@"
result=$?
if [ $result -eq 1 ]; then
    printf "\nlc: You may pass --help for further information on any subcommand\n" >&2
    exit 1
fi
if [ $result -gt 1 ]; then
    if [ $result -eq 130 ]; then
        printf "\n\nlc: linear-cli interrupted\n" >&2
        exit 130
    fi
    printf "lc: linear-cli failed %s\n" $result >&2
    lc "$@" --help 2>&1
    exit 1
fi
