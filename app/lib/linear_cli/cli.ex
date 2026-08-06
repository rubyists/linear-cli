defmodule LinearCli.CLI do
  @moduledoc """
  Entry point and `Optimus` argument-parsing spec.

  Ported from vendor/ruby-linear-cli/lib/linear/cli.rb and cli/caller.rb
  (global `--output`/`--debug` options, centralized error -> exit-code
  handling) plus each subcommand's own `commands/**` file for its flags.
  """

  alias LinearCli.CLI.Commands

  def main(argv, halt \\ &System.halt/1) do
    argv = argv |> normalize_aliases() |> normalize_help()
    {subcommand_path, parse_result} = Optimus.parse!(spec(), argv, halt)
    dispatch(subcommand_path, parse_result, halt)
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

  # Optimus only special-cases bare top-level `--help` and the `help <path...>`
  # form - `issue list --help` isn't recognized, and since `issue list` allows
  # unknown args (for bare issue ids), `--help` would silently be treated as an
  # issue id to look up instead of showing help. Rewrite `<path...> --help ...`
  # into `help <path...>` ourselves so `--help`/`-h` works at every subcommand
  # level, the way most CLIs expect.
  defp normalize_help(argv) do
    case Enum.split_while(argv, &(&1 not in ["--help", "-h"])) do
      {before, [_ | _]} when before != [] -> ["help" | before]
      _ -> argv
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

  defp run(fun, result, halt) do
    case fun.(result) do
      :ok -> :ok
      {:error, error} -> handle_error(error, result.options[:debug], halt)
    end
  end

  # Ported from CLI::Caller#call's `rescue NotFoundError` clause.
  defp handle_error(%Ash.Error.Unknown{errors: [%{value: [{:not_found, id}]} | _]}, debug, halt) do
    IO.puts(:stderr, "No issue found with id #{id}")
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
      name: "linear-cli",
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
                team: [short: "-t", long: "--team", help: "Show issues for only this team"]
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
