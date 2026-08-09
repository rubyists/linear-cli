defmodule LinearCli.CLI do
  @moduledoc """
  Entry point and `Optimus` argument-parsing spec.

  Ported from vendor/ruby-linear-cli/lib/linear/cli.rb and cli/caller.rb
  (global `--output`/`--debug` options, centralized error -> exit-code
  handling) plus each subcommand's own `commands/**` file for its flags.
  """

  alias LinearCli.CLI.Commands

  def main(argv, halt \\ &System.halt/1) do
    argv = argv |> normalize_aliases() |> normalize_help() |> default_to_issue_list()

    # Optimus.parse!/3 returns *either* {subcommand_path, parse_result}
    # (a subcommand matched) *or* a bare %Optimus.ParseResult{} (nothing
    # did - e.g. only global options were given, no subcommand token at
    # all). Assuming the tupled shape unconditionally crashed on that
    # second case with a bare MatchError. Normalize both to a uniform
    # {subcommand_path, parse_result} pair - an empty path hits dispatch/3's
    # existing "incomplete path" fallback (prints top-level help, exit 1),
    # exactly as it already does for e.g. `lc project` alone.
    {subcommand_path, parse_result} =
      case Optimus.parse!(spec(), argv, halt) do
        {path, result} -> {path, result}
        %Optimus.ParseResult{} = result -> {[], result}
      end

    try do
      dispatch(subcommand_path, parse_result, halt)
    rescue
      # Ported from CLI::Caller#call's catch-all `rescue StandardError`
      # clause - Ruby's rescue catches any unexpected raised exception, not
      # just a returned error value. `run/3`'s own `handle_error/3` call
      # only ever sees `{:error, reason}` *returned* from a command
      # function; it can't help with a genuine bug (e.g. a missing
      # `dispatch/3` clause for a valid-but-incomplete subcommand path, or
      # any other unhandled crash) that raises instead. This is that same
      # safety net at the top level, so a real bug degrades to a clean
      # message + exit 88 instead of a raw stack trace reaching the user.
      # `parse_result` is bound above, outside this try, specifically so
      # it's still in scope here (bindings from inside a `do` block aren't
      # visible in that same try's `rescue`, but outer-scope bindings are).
      exception -> handle_error(exception, parse_result.options[:debug], halt)
    end
  end

  # Optimus flags/options support exactly one `long:` name each (verified in
  # vendor/optimus/lib/optimus/flag.ex - no alias mechanism), but Ruby's
  # `--dev`/`--develop` (create.rb) and `--reason`/`--butwhy` (update.rb) are
  # both real, user-facing aliases people may actually type. Rewrite the
  # secondary spelling to the canonical one ourselves before Optimus ever
  # sees it, rather than dropping the alias.
  @flag_aliases %{"--develop" => "--dev", "--butwhy" => "--reason"}

  @doc false
  def normalize_aliases(argv) do
    Enum.map(argv, &Map.get(@flag_aliases, &1, &1))
  end

  # Ported from exe/scripts/lc.sh's own `[ "$#" -eq 0 ]` branch exactly
  # (including its stderr text) - a bare `lc` invocation defaults to
  # `issue list` rather than dumping top-level help.
  @doc false
  def default_to_issue_list([]) do
    IO.puts(:stderr, "No subcommand provided, defaulting to 'lc issue list'")
    IO.puts(:stderr, "lc --help to see subcommands")
    ["issue", "list"]
  end

  def default_to_issue_list(argv), do: argv

  # Optimus only special-cases bare top-level `--help` and the `help <path...>`
  # form - `issue list --help` isn't recognized, and since `issue list` allows
  # unknown args (for bare issue ids), `--help` would silently be treated as an
  # issue id to look up instead of showing help. Rewrite `<path...> --help ...`
  # into `help <path...>` ourselves so `--help`/`-h` works at every subcommand
  # level, the way most CLIs expect.
  #
  # `help <path>` only accepts bare subcommand names, not flags/values mixed
  # in - `lc issue update --close --help` (real usage, see bin/lclose) has
  # `--close` between the path and `--help`. Take only the leading run of
  # tokens that don't look like a flag/value (subcommand names never start
  # with "-" in this spec) rather than everything before `--help` verbatim,
  # so those extra tokens get dropped instead of breaking `help`'s own parse.
  defp normalize_help(argv) do
    case Enum.split_while(argv, &(&1 not in ["--help", "-h"])) do
      {before, [_ | _]} ->
        case Enum.take_while(before, &(not String.starts_with?(&1, "-"))) do
          [] -> argv
          path -> ["help" | path]
        end

      _ ->
        argv
    end
  end

  defp dispatch([:whoami], result, halt), do: run(&Commands.whoami/1, result, halt)
  defp dispatch([:version], result, halt), do: run(&Commands.version/1, result, halt)
  defp dispatch([:team, :list], result, halt), do: run(&Commands.team_list/1, result, halt)
  defp dispatch([:project, :list], result, halt), do: run(&Commands.project_list/1, result, halt)
  defp dispatch([:issue, :list], result, halt), do: run(&Commands.issue_list/1, result, halt)
  defp dispatch([:issue, :create], result, halt), do: run(&Commands.issue_create/1, result, halt)

  defp dispatch([:issue, :develop], result, halt),
    do: run(&Commands.issue_develop/1, result, halt)

  defp dispatch([:issue, :pr], result, halt), do: run(&Commands.issue_pr/1, result, halt)
  defp dispatch([:issue, :take], result, halt), do: run(&Commands.issue_take/1, result, halt)
  defp dispatch([:issue, :update], result, halt), do: run(&Commands.issue_update/1, result, halt)

  # A valid subcommand path that stops short of a leaf (e.g. `lc project`
  # with nothing after it) - Optimus itself doesn't require reaching a leaf,
  # it just returns an empty ParseResult, so without this clause it would
  # raise a bare FunctionClauseError. Show that path's own help instead,
  # exactly as `lc help project` would, and exit 1 (a usage error, not a
  # program bug - distinct from the crash-safety-net catch-all in main/1).
  defp dispatch(subcommand_path, _result, halt) do
    spec() |> Optimus.Help.help(subcommand_path, columns()) |> Enum.each(&IO.puts/1)
    halt.(1)
  end

  # Mirrors Optimus's own private columns/0 (vendor/optimus/lib/optimus.ex) -
  # not exported, so duplicated here rather than guessed at differently.
  defp columns do
    case Optimus.Term.width() do
      {:ok, width} -> width
      _ -> 80
    end
  end

  defp run(fun, result, halt) do
    case reject_unknown_flags(result.unknown) do
      :ok ->
        case fun.(result) do
          :ok -> :ok
          {:error, error} -> handle_error(error, result.options[:debug], halt)
        end

      {:error, error} ->
        handle_error(error, result.options[:debug], halt)
    end
  end

  # `issue list`/`take`/`update` all set `allow_unknown_args: true` so bare
  # tokens (e.g. `CRY-1`) can be captured as issue ids via `result.unknown`
  # rather than a declared positional arg (Optimus has no `type: :array`
  # equivalent - see their subcommand specs below). That same bucket also
  # silently swallows any *unrecognized flag* (e.g. a typo, or a real flag
  # this subcommand just doesn't have, like `--mine` on `issue list` - #2),
  # which then gets treated as an issue id to look up instead of erroring
  # clearly. Every other subcommand has `allow_unknown_args: false` (the
  # default), where Optimus itself already rejects unknown args before we
  # ever see a parse_result - so `result.unknown` is only ever non-empty here
  # for those three subcommands, and only ever contains genuine bare ids
  # once this filters out anything flag-shaped.
  defp reject_unknown_flags(unknown_tokens) do
    case Enum.filter(unknown_tokens, &String.starts_with?(&1, "-")) do
      [] ->
        :ok

      bad_flags ->
        {:error, {:smells_bad, "unrecognized option(s): #{Enum.join(bad_flags, ", ")}"}}
    end
  end

  # Ported from CLI::Caller#call's `rescue NotFoundError` clause.
  defp handle_error(%Ash.Error.Unknown{errors: [%{value: [{:not_found, id}]} | _]}, debug, halt) do
    IO.puts(:stderr, "No issue found with id #{id}")
    IO.puts(:stderr, "** Record not found, Cannot Continue **")
    maybe_print_backtrace(debug)
    halt.(66)
  end

  # Same NotFoundError intent as the clause above, but for Ash's own built-in
  # "get?: true action returned zero results" signal (e.g. Team.find/1 given
  # an unknown key) - a different shape than Issue's {:not_found, id} tuple
  # convention (verified: %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{}]}),
  # since it comes from Ash itself rather than one of our own manual actions.
  # Generic over `resource` so any future get?: true lookup gets the same
  # graceful message, not just Team.
  defp handle_error(
         %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{resource: resource} | _]},
         debug,
         halt
       ) do
    name = resource |> Module.split() |> List.last() |> String.downcase()
    IO.puts(:stderr, "No such #{name} found")
    IO.puts(:stderr, "** Record not found, Cannot Continue **")
    maybe_print_backtrace(debug)
    halt.(66)
  end

  # Ported from CLI::Caller#call's `rescue SmellsBad` clause. See
  # `LinearCli.CLI.IssueHelpers`'s moduledoc for where this tagged tuple
  # comes from.
  defp handle_error({:smells_bad, message}, debug, halt) do
    IO.puts(:stderr, message)
    IO.puts(:stderr, "** This smells bad! Bailing. **")
    maybe_print_backtrace(debug)
    halt.(22)
  end

  # Ported from CLI::Caller#call's catch-all `rescue StandardError` clause.
  defp handle_error(error, debug, halt) do
    IO.puts(:stderr, "What the heck is this? #{Exception.format_banner(:error, error)}")
    IO.puts(:stderr, "** WTH? Cannot Continue **")
    maybe_print_backtrace(debug)
    halt.(88)
  end

  defp maybe_print_backtrace(debug) when is_integer(debug) and debug > 0 do
    IO.puts(:stderr, Exception.format_stacktrace(Process.info(self(), :current_stacktrace)))
  end

  defp maybe_print_backtrace(_debug), do: :ok

  def spec do
    Optimus.new!(
      name: "lc",
      description: "CLI for interacting with Linear.app.",
      version: to_string(Application.spec(:linear_cli, :vsn) || "0.1.0"),
      about: "A CLI for interacting with Linear.app. Loosely based on the GitHub CLI",
      allow_unknown_args: false,
      parse_double_dash: true,
      options: [
        output: [
          long: "--output",
          short: "-o",
          help: "Output format",
          default: "text",
          global: true,
          parser: fn
            v when v in ["text", "json"] -> {:ok, v}
            v -> {:error, "must be one of: text, json (got #{inspect(v)})"}
          end
        ],
        debug: [
          long: "--debug",
          short: "-D",
          help: "Debug level (greater than 0 to see backtraces)",
          parser: :integer,
          default: 0,
          global: true
        ]
      ],
      subcommands: [
        whoami: [
          name: "whoami",
          about: "Get your own user info",
          flags: [
            teams: [short: "-t", long: "--teams", help: "Show teams"]
          ]
        ],
        version: [
          name: "version",
          about: "Show version"
        ],
        team: [
          name: "team",
          about: "Manage teams",
          subcommands: [
            list: [
              name: "list",
              about: "List teams",
              flags: [
                no_mine: [long: "--no-mine", help: "List all teams, not just your own"]
              ]
            ]
          ]
        ],
        project: [
          name: "project",
          about: "Manage projects",
          subcommands: [
            list: [
              name: "list",
              about: "List projects",
              flags: [
                mine: [short: "-m", long: "--mine", help: "Only show my projects"]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Show projects for only this team"]
              ]
            ]
          ]
        ],
        issue: [
          name: "issue",
          about: "Manage issues",
          subcommands: [
            list: [
              name: "list",
              about: "List issues",
              allow_unknown_args: true,
              flags: [
                unassigned: [
                  short: "-u",
                  long: "--unassigned",
                  help: "Show unassigned issues only"
                ],
                no_mine: [
                  long: "--no-mine",
                  help: "List the most recent issues, not just your own"
                ],
                full: [short: "-f", long: "--full", help: "Show full issue details"]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Show issues for only this team"],
                project: [
                  short: "-p",
                  long: "--project",
                  help:
                    "Show issues for only this project. Can be name, URL, ID, or - to select from a list"
                ]
              ]
            ],
            create: [
              name: "create",
              about:
                "Create a new issue. If you do not pass any options, you will be prompted " <>
                  "for the required information.",
              options: [
                description: [short: "-d", long: "--description", help: "Issue Description"],
                labels: [
                  short: "-l",
                  long: "--labels",
                  help: "Labels for the issue (Comma separated list)",
                  parser: fn v -> {:ok, String.split(v, ",")} end
                ],
                project: [short: "-p", long: "--project", help: "Project Identifier"],
                team: [short: "-T", long: "--team", help: "Team Identifier"],
                title: [short: "-t", long: "--title", help: "Issue Title"]
              ],
              flags: [
                develop: [long: "--dev", help: "Start development after creating the issue"]
              ]
            ],
            develop: [
              name: "develop",
              about: "Start or update development status of an issue",
              args: [
                issue_id: [value_name: "ISSUE_ID", help: "The Issue (i.e. ISS-1)", required: true]
              ]
            ],
            pr: [
              name: "pr",
              about: "Create a PR for an issue and push it to the remote",
              args: [
                issue_id: [value_name: "ISSUE_ID", help: "The Issue (i.e. CRY-1)", required: true]
              ],
              options: [
                title: [long: "--title", help: "The title of the PR"],
                description: [long: "--description", help: "The description of the PR"]
              ]
            ],
            take: [
              name: "take",
              about: "Assign one or more issues to yourself",
              allow_unknown_args: true
            ],
            update: [
              name: "update",
              about: "Update an issue",
              allow_unknown_args: true,
              flags: [
                cancel: [long: "--cancel", help: "Cancel the issue"],
                close: [long: "--close", help: "Close the issue"],
                trash: [
                  long: "--trash",
                  help: "Also trash the issue (--close and --cancel support this option)"
                ]
              ],
              options: [
                comment: [
                  short: "-m",
                  long: "--comment",
                  help: "Comment to add to the issue. - open an editor"
                ],
                project: [
                  short: "-p",
                  long: "--project",
                  help: "Project to move the issue to. - select from a list"
                ],
                reason: [long: "--reason", help: "Reason for closing the issue. - open an editor"]
              ]
            ]
          ]
        ]
      ]
    )
  end
end
