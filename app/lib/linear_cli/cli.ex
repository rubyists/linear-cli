defmodule LinearCli.CLI do
  @moduledoc """
  Entry point and `Optimus` argument-parsing spec.

  Ported from vendor/ruby-linear-cli/lib/linear/cli.rb and cli/caller.rb
  (global `--output`/`--debug` options, centralized error -> exit-code
  handling) plus each subcommand's own `commands/**` file for its flags.
  """

  alias LinearCli.CLI.Commands

  @workflow_state_types ~w(triage backlog unstarted started completed canceled duplicate)

  def main(argv, halt \\ &System.halt/1) do
    argv =
      argv
      |> normalize_aliases()
      |> normalize_subcommand_aliases()
      |> normalize_help()
      |> default_to_issue_list()

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
      exception ->
        debug = is_struct(parse_result, Optimus.ParseResult) && parse_result.options[:debug]
        handle_error(exception, debug, halt)
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

  # Optimus's subcommand spec has no alias mechanism either (verified:
  # vendor/optimus/lib/optimus/subcommand.ex), but Ruby registers every one
  # of these via each command module's `ALIASES` constant (cli.rb's
  # `register`/`register_sub!`) - real, user-facing shortcuts people type
  # (`lc i dev CRY-37`). Sourced from those constants directly, not the
  # Readme's prose list, which was missing several (`new`/`add`/`me`/`who`/
  # `teams`/`projects`/`issues`/`t`/`p`/`v`). `completion` (dry-cli-specific)
  # and `console`/`pry` (Ruby dev tooling) have no equivalent here, so
  # they're intentionally not included.
  @command_aliases %{
    "me" => "whoami",
    "w" => "whoami",
    "who" => "whoami",
    "whodat" => "whoami",
    "v" => "version",
    "i" => "issue",
    "issues" => "issue",
    "t" => "team",
    "teams" => "team",
    "p" => "project",
    "projects" => "project"
  }

  # `take` has no alias in Ruby either - every issue subcommand not listed
  # here (just `take`) is only ever reachable by its canonical name there
  # too, so this port doesn't need to invent one.
  @subcommand_aliases %{
    "issue" => %{
      "a" => "assign",
      "c" => "create",
      "new" => "create",
      "add" => "create",
      "d" => "develop",
      "dev" => "develop",
      "l" => "list",
      "ls" => "list",
      "m" => "move",
      "mv" => "move",
      "s" => "status",
      "st" => "status",
      "stat" => "status",
      "u" => "update",
      "pull-request" => "pr"
    },
    "team" => %{"l" => "list", "ls" => "list"},
    "project" => %{"l" => "list", "ls" => "list"},
    "profile" => %{"l" => "list", "ls" => "list"}
  }

  @doc false
  def normalize_subcommand_aliases([first | rest]) do
    canonical_first = Map.get(@command_aliases, first, first)

    case {Map.fetch(@subcommand_aliases, canonical_first), rest} do
      {{:ok, sub_aliases}, [second | more]} ->
        [canonical_first, Map.get(sub_aliases, second, second) | more]

      _ ->
        [canonical_first | rest]
    end
  end

  def normalize_subcommand_aliases(argv), do: argv

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

  defp dispatch([:team, :favorite], result, halt),
    do: run(&Commands.team_favorite/1, result, halt)

  defp dispatch([:team, :unfavorite], result, halt),
    do: run(&Commands.team_unfavorite/1, result, halt)

  defp dispatch([:project, :list], result, halt), do: run(&Commands.project_list/1, result, halt)

  defp dispatch([:project, :favorite], result, halt),
    do: run(&Commands.project_favorite/1, result, halt)

  defp dispatch([:project, :unfavorite], result, halt),
    do: run(&Commands.project_unfavorite/1, result, halt)

  defp dispatch([:project, :update], result, halt),
    do: run(&Commands.project_update/1, result, halt)

  defp dispatch([:profile, :create], result, halt),
    do: run(&Commands.profile_create/1, result, halt)

  defp dispatch([:profile, :list], result, halt), do: run(&Commands.profile_list/1, result, halt)
  defp dispatch([:profile, :use], result, halt), do: run(&Commands.profile_use/1, result, halt)
  defp dispatch([:profile, :show], result, halt), do: run(&Commands.profile_show/1, result, halt)

  defp dispatch([:profile, :delete], result, halt),
    do: run(&Commands.profile_delete/1, result, halt)

  defp dispatch([:profile, :clear], result, halt),
    do: run(&Commands.profile_clear/1, result, halt)

  defp dispatch([:issue, :list], result, halt), do: run(&Commands.issue_list/1, result, halt)
  defp dispatch([:issue, :assign], result, halt), do: run(&Commands.issue_assign/1, result, halt)
  defp dispatch([:issue, :create], result, halt), do: run(&Commands.issue_create/1, result, halt)

  defp dispatch([:issue, :develop], result, halt),
    do: run(&Commands.issue_develop/1, result, halt)

  defp dispatch([:issue, :pr], result, halt), do: run(&Commands.issue_pr/1, result, halt)
  defp dispatch([:issue, :move], result, halt), do: run(&Commands.issue_move/1, result, halt)
  defp dispatch([:issue, :take], result, halt), do: run(&Commands.issue_take/1, result, halt)
  defp dispatch([:issue, :status], result, halt), do: run(&Commands.issue_status/1, result, halt)
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

  # `issue list`/`take`/`status`/`update` all set `allow_unknown_args: true` so bare
  # tokens (e.g. `CRY-1`) can be captured as issue ids via `result.unknown`
  # rather than a declared positional arg (Optimus has no `type: :array`
  # equivalent - see their subcommand specs below). That same bucket also
  # silently swallows any *unrecognized flag* (e.g. a typo, or a real flag
  # this subcommand just doesn't have, like `--mine` on `issue list` - #2),
  # which then gets treated as an issue id to look up instead of erroring
  # clearly. Every other subcommand has `allow_unknown_args: false` (the
  # default), where Optimus itself already rejects unknown args before we
  # ever see a parse_result - so `result.unknown` is only ever non-empty here
  # for those four subcommands, and only ever contains genuine bare ids
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

  # LinearCli.Api.call/2's {:error, :missing_api_key} (LINEAR_API_KEY not
  # set), reached through any of the Ash manual actions that wrap it -
  # Ash's own action pipeline stringifies the original reason into
  # Ash.Error.Unknown.UnknownError's :error field ("unknown error:
  # :missing_api_key", verified directly) rather than preserving the atom,
  # hence the exact-string match below instead of `error: :missing_api_key`.
  # A plain pattern match (no guard - `=~` isn't guard-safe) degrades
  # gracefully to the generic catch-all below if Ash's wrapping format ever
  # changes, rather than raising a fresh error of its own. A missing API key
  # is a configuration problem, not a surprising crash - give it a clear
  # message and sysexits.h's EX_CONFIG (78) instead of the catch-all's raw
  # error dump. See #74.
  defp handle_error(
         %Ash.Error.Unknown{
           errors: [%Ash.Error.Unknown.UnknownError{error: "unknown error: :missing_api_key"} | _]
         },
         debug,
         halt
       ) do
    IO.puts(:stderr, "LINEAR_API_KEY is not set.")

    IO.puts(
      :stderr,
      "Set it to your Linear API key - see https://linear.app/settings/account/security"
    )

    IO.puts(:stderr, "** Missing configuration, cannot continue **")
    maybe_print_backtrace(debug)
    halt.(78)
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

  # Safety net for any LinearCli.Api.call/2 site whose {:error, {:graphql_errors,
  # errors}} return was not already converted to a domain-specific error tuple
  # (e.g. by fetch_one/1's ENTITY_NOT_FOUND clause in issue.ex). Ash wraps the
  # raw tuple in %Ash.Error.Unknown.UnknownError{error: {:graphql_errors, ...}}.
  # Extracting the first error's "message" gives a human-readable error rather
  # than falling through to the opaque "What the heck is this?" catch-all.
  defp handle_error(
         %Ash.Error.Unknown{
           errors: [%{value: [{:graphql_errors, [%{"message" => message} | _]}]} | _]
         },
         debug,
         halt
       ) do
    IO.puts(:stderr, "Linear API error: #{message}")
    IO.puts(:stderr, "** API Error, Cannot Continue **")
    maybe_print_backtrace(debug)
    halt.(88)
  end

  # LinearCli.Api.call/2's {:error, {:http_error, status, body}} for 401/403 -
  # bad or expired API key. Give a targeted message instead of dumping the raw
  # error structure. ManualRead else clauses normalize the 3-tuple to 2-tuple
  # {:http_error, status} so Ash (via Splode) stores it in value: [{:http_error, status}].
  defp handle_error(
         %Ash.Error.Unknown{errors: [%{value: [{:http_error, status}]} | _]},
         debug,
         halt
       )
       when status in [401, 403] do
    IO.puts(:stderr, "Linear API authentication failed (HTTP #{status}).")
    IO.puts(:stderr, "Check that LINEAR_API_KEY is valid.")
    IO.puts(:stderr, "** Authentication error, cannot continue **")
    maybe_print_backtrace(debug)
    halt.(77)
  end

  # LinearCli.Api.call/2's {:error, {:http_error, status, body}} for any other
  # non-200 status (rate-limit 429, server errors 5xx, etc.).
  defp handle_error(
         %Ash.Error.Unknown{errors: [%{value: [{:http_error, status}]} | _]},
         debug,
         halt
       ) do
    IO.puts(:stderr, "Linear API returned HTTP #{status}.")
    IO.puts(:stderr, "** API Error, Cannot Continue **")
    maybe_print_backtrace(debug)
    halt.(88)
  end

  # LinearCli.Api.call/2's {:error, {:transport_error, exception}} - DNS failure,
  # timeout, connection refused, etc. Ash wraps as %{value: [{:transport_error, ...}]}.
  defp handle_error(
         %Ash.Error.Unknown{errors: [%{value: [{:transport_error, _exception}]} | _]},
         debug,
         halt
       ) do
    IO.puts(:stderr, "Could not reach the Linear API.")
    IO.puts(:stderr, "** Network error, cannot continue **")
    maybe_print_backtrace(debug)
    halt.(69)
  end

  # LinearCli.Api.call/2's {:error, {:unexpected_response, body}} - a 200 with
  # neither "data" nor "errors", or a caller that received an unexpected data shape.
  # More specific than the catch-all so users get a targeted message.
  defp handle_error(
         %Ash.Error.Unknown{errors: [%{value: [{:unexpected_response, _body}]} | _]},
         debug,
         halt
       ) do
    IO.puts(:stderr, "Linear API returned an unexpected response.")
    IO.puts(:stderr, "** API Error, Cannot Continue **")
    maybe_print_backtrace(debug)
    halt.(88)
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

  defp parse_states(value) do
    states =
      value
      |> split_filter_values()
      |> Enum.map(&normalize_state/1)

    case Enum.find(states, &(&1 not in @workflow_state_types)) do
      nil ->
        {:ok, states}

      state ->
        {:error,
         "unknown state #{inspect(state)}, must be one of: #{Enum.join(@workflow_state_types, ", ")}"}
    end
  end

  defp parse_statuses(value), do: {:ok, split_filter_values(value)}

  defp split_filter_values(value) do
    value
    |> String.split(",", trim: true)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp normalize_state("cancelled"), do: "canceled"
  defp normalize_state(state), do: String.downcase(state)

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
                no_mine: [
                  short: "-N",
                  long: "--no-mine",
                  help: "List all teams, not just your own"
                ],
                all: [long: "--all", help: "Ignore favorites (doesn't affect --no-mine)"]
              ]
            ],
            favorite: [
              name: "favorite",
              about: "Favorite a team - list defaults to favorites once any exist",
              args: [team: [value_name: "TEAM", help: "Team key or id", required: true]]
            ],
            unfavorite: [
              name: "unfavorite",
              about: "Un-favorite a team",
              args: [team: [value_name: "TEAM", help: "Team key or id", required: true]]
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
                mine: [short: "-m", long: "--mine", help: "Only show my projects"],
                all: [long: "--all", help: "Ignore favorites (doesn't affect --mine/--team)"]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Show projects for only this team"]
              ]
            ],
            favorite: [
              name: "favorite",
              about: "Favorite a project - list defaults to favorites once any exist",
              args: [
                project: [
                  value_name: "PROJECT",
                  help: "Project name, URL, ID, or search term",
                  required: true
                ]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Scope project search to this team"]
              ]
            ],
            unfavorite: [
              name: "unfavorite",
              about: "Un-favorite a project",
              args: [
                project: [
                  value_name: "PROJECT",
                  help: "Project name, URL, ID, or search term",
                  required: true
                ]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Scope project search to this team"]
              ]
            ],
            update: [
              name: "update",
              about: "Post a status update to a project",
              args: [
                project: [
                  value_name: "PROJECT",
                  help: "Project name, URL, ID, or search term",
                  required: true
                ]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Scope project search to this team"],
                body: [short: "-b", long: "--body", help: "The update's content (markdown)"],
                health: [
                  long: "--health",
                  help: "Project health: onTrack, atRisk, or offTrack",
                  parser: fn
                    v when v in ["onTrack", "atRisk", "offTrack"] -> {:ok, v}
                    v -> {:error, "must be one of: onTrack, atRisk, offTrack (got #{inspect(v)})"}
                  end
                ]
              ]
            ]
          ]
        ],
        profile: [
          name: "profile",
          about: "Manage saved team/project profiles",
          subcommands: [
            create: [
              name: "create",
              about: "Save a new profile",
              args: [name: [value_name: "NAME", help: "Profile name", required: true]],
              options: [
                team: [short: "-t", long: "--team", help: "Default team for this profile"],
                project: [
                  short: "-p",
                  long: "--project",
                  help: "Default project for this profile"
                ]
              ]
            ],
            list: [name: "list", about: "List saved profiles"],
            use: [
              name: "use",
              about: "Switch to a saved profile",
              args: [name: [value_name: "NAME", help: "Profile name", required: true]]
            ],
            show: [name: "show", about: "Show the active profile"],
            delete: [
              name: "delete",
              about: "Delete a saved profile",
              args: [name: [value_name: "NAME", help: "Profile name", required: true]]
            ],
            clear: [
              name: "clear",
              about: "Deactivate the active profile without deleting it"
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
                  short: "-N",
                  long: "--no-mine",
                  help: "List the most recent issues, not just your own"
                ],
                no_profile: [
                  long: "--no-profile",
                  help: "Ignore the active profile's team/project defaults"
                ],
                full: [short: "-f", long: "--full", help: "Show full issue details"],
                all: [
                  long: "--all",
                  help: "Show all issues including completed and cancelled"
                ]
              ],
              options: [
                team: [short: "-t", long: "--team", help: "Show issues for only this team"],
                project: [
                  short: "-p",
                  long: "--project",
                  help:
                    "Show issues for only this project. Can be name, URL, ID, or - to select from a list"
                ],
                state: [
                  long: "--state",
                  help:
                    "Filter by workflow state type(s): triage, backlog, unstarted, started, completed, canceled, duplicate (comma-separated)",
                  parser: &parse_states/1
                ],
                status: [
                  short: "-s",
                  long: "--status",
                  help: "Filter by friendly workflow status name(s) (comma-separated)",
                  parser: &parse_statuses/1
                ]
              ]
            ],
            assign: [
              name: "assign",
              about: "Assign an issue to a team member",
              args: [
                issue_id: [value_name: "ISSUE_ID", help: "The Issue (i.e. CRY-1)", required: true]
              ],
              options: [
                assignee: [
                  short: "-a",
                  long: "--assignee",
                  help: "Team member name to assign to (prompts if omitted)"
                ],
                status: [
                  short: "-s",
                  long: "--status",
                  help: "Workflow state name to set after assigning (e.g. \"In Progress\")"
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
            status: [
              name: "status",
              about: "Change workflow state (ISSUE_ID...)",
              allow_unknown_args: true,
              options: [
                status: [
                  short: "-s",
                  long: "--status",
                  help: "Workflow state name to set (prompts if omitted)"
                ],
                comment: [
                  short: "-m",
                  long: "--comment",
                  help: "Comment to add alongside the status change"
                ]
              ]
            ],
            take: [
              name: "take",
              about: "Assign one or more issues to yourself",
              allow_unknown_args: true,
              options: [
                status: [
                  short: "-s",
                  long: "--status",
                  help: "Workflow state name to set after self-assigning (e.g. \"In Progress\")"
                ]
              ]
            ],
            move: [
              name: "move",
              about: "Move one or more issues to a project (ISSUE_ID...)",
              allow_unknown_args: true,
              flags: [
                dry_run: [
                  long: "--dry-run",
                  help: "Preview moves without executing them"
                ],
                yes: [
                  short: "-y",
                  long: "--yes",
                  help: "Skip confirmation prompt"
                ]
              ],
              options: [
                project: [
                  short: "-p",
                  long: "--project",
                  help: "Target project name, URL, ID, or - to select from a list"
                ],
                team: [
                  short: "-t",
                  long: "--team",
                  help: "Scope project search to this team"
                ]
              ]
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
                description: [
                  short: "-d",
                  long: "--description",
                  help: "Update the issue description. - to open an editor"
                ],
                project: [
                  short: "-p",
                  long: "--project",
                  help: "Project to move the issue to. - select from a list"
                ],
                status: [
                  short: "-s",
                  long: "--status",
                  help: "Workflow state name to use with --close or --cancel"
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
