defmodule LinearCli.CLI.Commands.Teams do
  @moduledoc """
  Team commands: list, favorite, and unfavorite.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/team/.
  """

  alias LinearCli.CLI.{Display, Prompt}
  alias LinearCli.{Favorites, Linear}

  @doc "Ported from commands/team/list.rb. Ruby's `--mine` defaults true."
  def team_list(%{flags: flags, options: options}) do
    result = if flags.no_mine, do: Linear.teams(), else: Linear.my_teams()

    with {:ok, teams} <- result do
      Display.show(filter_favorites(teams, flags.all, "team", & &1.key), %{
        output: options.output
      })

      :ok
    end
  end

  @doc """
  New in this port - Ruby has no equivalent. Favorites a team
  (`LinearCli.Favorites`) - once any team is favorited, `team list`
  defaults to showing just favorites (`--all` overrides).
  """
  def team_favorite(%{args: %{team: key}}) do
    with {:ok, team} <- Linear.find_team(key) do
      Favorites.add("team", team.key)
      Prompt.ok("Favorited team #{team.key}")
      :ok
    end
  end

  @doc "New in this port - Ruby has no equivalent. Un-favorites a team."
  def team_unfavorite(%{args: %{team: key}}) do
    with {:ok, team} <- Linear.find_team(key) do
      Favorites.remove("team", team.key)
      Prompt.ok("Un-favorited team #{team.key}")
      :ok
    end
  end

  # Once any favorite of `kind` exists, narrows `records` down to just
  # those (matched via `key_fun`) - invisible to anyone who's never
  # favorited anything, since an empty favorites list leaves `records`
  # untouched. `all?` (the new `--all` flag) always shows everything,
  # bypassing the favorites lookup entirely.
  defp filter_favorites(records, true, _kind, _key_fun), do: records

  defp filter_favorites(records, _all?, kind, key_fun) do
    case Favorites.list(kind) do
      [] -> records
      favorite_values -> Enum.filter(records, &(key_fun.(&1) in favorite_values))
    end
  end
end
