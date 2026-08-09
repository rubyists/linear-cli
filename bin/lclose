#!/usr/bin/env bash
if [[ "$*" =~ "--help" ]]
then
    printf "This wrapper adds the --close option to the 'issue update' command.\n" >&2
    printf "It is used to close one or many issues. The issues are specified by their ID/slugs.\n" >&2
    printf "For closing multiple issues, you really want to pass --reason so you do not get prompted for each issue.\n\n" >&2
    exec lc issue update --close --help
fi
exec lc issue update --close "$@"
