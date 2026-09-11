defmodule LinearCli.CLI.Issue.Identifiers do
  @moduledoc """
  Bare-issue-ID expansion: turns a plain integer string (e.g. `"1234"`) into
  a team-prefixed identifier (`"CRY-1234"`) by resolving a team key.

  Extracted from `LinearCli.CLI.IssueHelpers`. The single public function,
  `expand_issue_id/1`, is called by every command that accepts an issue
  identifier from the user so that bare numbers work wherever full identifiers
  do.

  Team resolution order (never a hard error short of the user having no teams
  at all): the active profile's team (`LinearCli.Profiles.default_team/0`) ->
  favorited teams (`LinearCli.Favorites.list/1`, single favorite used directly,
  several prompted) -> a prompt across every team the user belongs to
  (`LinearCli.CLI.WhatFor.ask_for_team/0`).
  """

  alias LinearCli.CLI.{Prompt, WhatFor}
  alias LinearCli.{Favorites, Profiles}

  # A "bare" issue id is just digits - anything with a `-` (an already
  # team-prefixed identifier, e.g. "CRY-1234") or that otherwise doesn't
  # look like an id at all (a UUID) passes through `expand_issue_id/1`
  # unchanged.
  @bare_issue_id_regex ~r/^\d+$/

  @doc """
  Expands a bare issue number (`~r/^\\d+$/`, e.g. `"1234"`) to a full
  team-prefixed identifier (`"CRY-1234"`) by resolving a team key via
  `resolve_bare_team/0`. Anything else (an already-prefixed identifier, a
  UUID) is returned unchanged.

  Team resolution order, never a hard error short of the user having no
  teams at all: the active profile's team (`LinearCli.Profiles.default_team/0`)
  -> favorited teams (`LinearCli.Favorites.list/1`, single favorite used
  directly, several prompted) -> a prompt across every team the user
  belongs to (`LinearCli.CLI.WhatFor.ask_for_team/0`).
  """
  @spec expand_issue_id(String.t()) :: String.t()
  def expand_issue_id(issue_id) do
    if Regex.match?(@bare_issue_id_regex, issue_id) do
      "#{resolve_bare_team()}-#{issue_id}"
    else
      issue_id
    end
  end

  defp resolve_bare_team do
    case Profiles.default_team() do
      nil -> resolve_bare_team_from_favorites()
      team_key -> team_key
    end
  end

  defp resolve_bare_team_from_favorites do
    case Favorites.list("team") do
      [] -> WhatFor.ask_for_team().key
      [team_key] -> team_key
      team_keys -> Prompt.select("Choose a team", Enum.map(team_keys, &{&1, &1}))
    end
  end
end
