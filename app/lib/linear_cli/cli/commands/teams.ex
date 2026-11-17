defmodule LinearCli.CLI.Commands.Teams do
  @moduledoc """
  Team commands: list, favorite, and unfavorite.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/team/.
  """

  alias LinearCli.CLI.{Display, Output, Prompt}
  alias LinearCli.{Favorites, Linear}

  @doc "Ported from commands/team/list.rb. Ruby's `--mine` defaults true."
  def team_list(%{flags: flags, options: options}) do
    with {:ok, cached} <- Favorites.records("team", flags.all),
         {:ok, teams} <- listed_teams(cached, flags) do
      Display.show(teams, %{output: options.output})
      :ok
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Favorites a team
  (`LinearCli.Favorites`) - once any team is favorited, `team list`
  defaults to showing just favorites (`--all` overrides).
  """
  def team_favorite(%{args: %{team: key}, options: options}) do
    with {:ok, team} <- Linear.find_team(key) do
      :ok = Favorites.save("team", team)

      if Output.json?(options) do
        Output.success("team_favorite", %{"team" => team.key}, options)
      else
        Prompt.ok("Favorited team #{team.key}")
      end

      :ok
    end
  end

  @doc "New in this port - Ruby has no equivalent. Un-favorites a team."
  def team_unfavorite(%{args: %{team: key}, options: options}) do
    with {:ok, team} <- Linear.find_team(key) do
      Favorites.remove("team", team.key)

      if Output.json?(options) do
        Output.success("team_unfavorite", %{"team" => team.key}, options)
      else
        Prompt.ok("Un-favorited team #{team.key}")
      end

      :ok
    end
  end

  defp listed_teams(nil, %{no_mine: true}), do: Linear.teams()
  defp listed_teams(nil, _flags), do: Linear.my_teams()
  defp listed_teams(teams, _flags), do: {:ok, teams}
end
