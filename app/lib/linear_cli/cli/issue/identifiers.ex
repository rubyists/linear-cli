defmodule LinearCli.CLI.Issue.Identifiers do
  @moduledoc """
  Bare-issue-ID expansion: turns a plain integer string (e.g. `"1234"`) into
  a team-prefixed identifier (`"CRY-1234"`) by resolving a team key.

  Extracted from the former `LinearCli.CLI.IssueHelpers`. The single public function,
  `expand_issue_id/1`, is called by every command that accepts an issue
  identifier from the user so that bare numbers work wherever full identifiers
  do.

  Text-mode team resolution uses the active profile's team
  (`LinearCli.Profiles.default_team/0`), then favorited teams
  (`LinearCli.Favorites.list/1`), then a prompt across every team the user
  belongs to (`LinearCli.CLI.WhatFor.ask_for_team/0`). JSON mode uses the same
  deterministic sources, but returns an error instead of prompting when a
  choice is required.
  """

  alias LinearCli.CLI.{Prompt, WhatFor}
  alias LinearCli.{Favorites, Linear, Profiles}

  # A "bare" issue id is just digits - anything with a `-` (an already
  # team-prefixed identifier, e.g. "CRY-1234") or that otherwise doesn't
  # look like an id at all (a UUID) passes through `expand_issue_id/1`
  # unchanged.
  @bare_issue_id_regex ~r/^\d+$/

  @doc """
  Expands a bare issue number (`~r/^\\d+$/`, e.g. `"1234"`) to a full
  team-prefixed identifier (`"CRY-1234"`) by resolving a team key via
  `resolve_bare_team/1`. Anything else (an already-prefixed identifier, a
  UUID) is returned unchanged.

  The one-argument form keeps text-mode behavior. The output-aware form returns
  `{:ok, identifier}` or `{:error, reason}` and rejects team prompts in JSON
  mode.

  Text mode resolves teams from the active profile, one favorite, or a prompt
  across the user's teams. JSON mode accepts only deterministic resolution
  and returns an error when a team choice would require a prompt.
  """
  @spec expand_issue_id(String.t()) :: String.t()
  def expand_issue_id(issue_id) do
    case expand_issue_id(issue_id, output: "text") do
      {:ok, expanded_id} -> expanded_id
      {:error, reason} -> raise "Could not expand issue id #{issue_id}: #{inspect(reason)}"
    end
  end

  @spec expand_issue_id(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def expand_issue_id(issue_id, opts) do
    if Regex.match?(@bare_issue_id_regex, issue_id) do
      with {:ok, team_key} <- resolve_bare_team(opts) do
        {:ok, "#{team_key}-#{issue_id}"}
      end
    else
      {:ok, issue_id}
    end
  end

  @spec expand_issue_ids([String.t()], keyword()) ::
          {:ok, [String.t()]} | {:error, term()}
  def expand_issue_ids(issue_ids, opts) do
    Enum.reduce_while(issue_ids, {:ok, []}, fn issue_id, {:ok, expanded_ids} ->
      case expand_issue_id(issue_id, opts) do
        {:ok, expanded_id} -> {:cont, {:ok, [expanded_id | expanded_ids]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, expanded_ids} -> {:ok, Enum.reverse(expanded_ids)}
      error -> error
    end
  end

  defp resolve_bare_team(opts) do
    case Profiles.default_team() do
      nil -> resolve_bare_team_from_favorites(opts)
      team_key -> {:ok, team_key}
    end
  end

  defp resolve_bare_team_from_favorites(opts) do
    case Favorites.list("team") do
      [] ->
        resolve_bare_team_from_available_teams(opts)

      [team_key] ->
        {:ok, team_key}

      team_keys ->
        if Keyword.get(opts, :output, "text") == "json" do
          {:error, ambiguous_team_error()}
        else
          {:ok, Prompt.select("Choose a team", Enum.map(team_keys, &{&1, &1}))}
        end
    end
  end

  defp resolve_bare_team_from_available_teams(opts) do
    if Keyword.get(opts, :output, "text") == "json" do
      case Linear.my_teams() do
        {:ok, [team]} -> {:ok, team.key}
        {:ok, _teams} -> {:error, ambiguous_team_error()}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, WhatFor.ask_for_team().key}
    end
  end

  defp ambiguous_team_error do
    {:smells_bad,
     "JSON output cannot prompt for a team while expanding a bare issue ID. " <>
       "Use a full team-prefixed ID, an active profile, or one favorite team."}
  end
end
