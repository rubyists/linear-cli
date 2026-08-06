defmodule LinearCli.CLI.Commands do
  @moduledoc """
  The logic behind each subcommand: fetch via `LinearCli.Linear`, display the
  result. Ported from vendor/ruby-linear-cli/lib/linear/commands/**.
  """

  alias LinearCli.CLI.Display
  alias LinearCli.Linear

  @doc "Ported from commands/whoami.rb."
  def whoami(%{flags: flags, options: options}) do
    with {:ok, user} <- Linear.me() do
      Display.show(user, %{output: options.output, teams: flags.teams})
      :ok
    end
  end

  @doc "Ported from commands/version.rb."
  def version(_result) do
    IO.puts(to_string(Application.spec(:linear_cli, :vsn)))
    :ok
  end

  @doc "Ported from commands/team/list.rb. Ruby's `--mine` defaults true."
  def team_list(%{flags: flags, options: options}) do
    result = if flags.no_mine, do: Linear.teams(), else: Linear.my_teams()

    with {:ok, teams} <- result do
      Display.show(teams, %{output: options.output})
      :ok
    end
  end

  @doc "Ported from commands/project/list.rb. Ruby's `--mine` defaults false."
  def project_list(%{flags: flags, options: options}) do
    result = if flags.mine, do: Linear.my_projects(), else: Linear.projects()

    with {:ok, projects} <- result do
      Display.show(projects, %{output: options.output})
      :ok
    end
  end

  @doc """
  Ported from commands/issue/list.rb + operations/issue/list.rb.

  `--project`/`-p` (which needs the interactive project picker from
  `CLI::Projects#project_for`) isn't wired up yet - deferred to the phase
  that builds `Owl`-based prompts.
  """
  def issue_list(%{flags: flags, options: options, unknown: ids}) do
    input = %{
      ids: ids,
      mine: !flags.no_mine,
      unassigned: flags.unassigned,
      team_key: options.team
    }

    with {:ok, issues} <- Linear.issues(input) do
      Display.show(issues, %{output: options.output, full: flags.full})
      :ok
    end
  end
end
