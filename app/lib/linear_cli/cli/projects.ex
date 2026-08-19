defmodule LinearCli.CLI.Projects do
  @moduledoc """
  Fuzzy-match-then-prompt-to-disambiguate logic for resolving a user-supplied
  `-p`/`--project` search term (id, url, name, slug, or description
  fragment) to an actual `LinearCli.Linear.Project`.

  Ported from vendor/ruby-linear-cli/lib/linear/cli/projects.rb
  (`Rubyists::Linear::CLI::Projects#project_for`, `#project_scores`,
  `#ask_for_projects`).

  Interactive fallback goes through `LinearCli.CLI.Prompt.select/2` and
  `LinearCli.CLI.Prompt.warn/1`.
  """

  alias LinearCli.CLI.Prompt
  alias LinearCli.Linear.Project

  @doc """
  Ported from Ruby's `CLI::Projects#project_for`.

  Resolves `search` against `projects`:

    * `projects` empty -> `nil`
    * `search` is `nil` -> delegates straight to `ask_for_projects/2` (no
      "no project found" warning, since no search was attempted)
    * `search` given but no project scores positively -> delegates to
      `ask_for_projects/2` (which warns "No project found matching
      \#{search}." and then prompts across *all* `projects`)
    * any positively-scoring candidate scores `100` (an exact
      id/url/slug/name match) -> that project, no prompt
    * otherwise -> `LinearCli.CLI.Prompt.select/2` over the positively
      scoring candidates (lowest score first, per `project_scores/2`'s
      ascending sort) followed by the remaining, non-matching projects
  """
  def project_for(projects, search \\ nil)

  def project_for([], _search), do: nil

  def project_for(projects, nil), do: ask_for_projects(projects, nil)

  def project_for(projects, search) do
    case project_scores(projects, search) do
      [] ->
        ask_for_projects(projects, search)

      possibles ->
        case Enum.find(possibles, &(Project.match_score?(&1, search) == 100)) do
          nil ->
            selections = possibles ++ (projects -- possibles)
            Prompt.select("Project:", Enum.map(selections, &{&1.name, &1}))

          exact ->
            exact
        end
    end
  end

  @doc """
  Ported from Ruby's `CLI::Projects#project_scores`. The subset of
  `projects` with a positive `Project.match_score?/2` against
  `search_term`, ascending by score (lowest positive match first) - matches
  Ruby's `sort_by` (not reversed) exactly.
  """
  def project_scores(projects, search_term) do
    projects
    |> Enum.filter(&(Project.match_score?(&1, search_term) > 0))
    |> Enum.sort_by(&Project.match_score?(&1, search_term))
  end

  @doc """
  Ported from Ruby's `CLI::Projects#ask_for_projects`.

  Warns (via `LinearCli.CLI.Prompt.warn/1`) that nothing matched `search`
  when `search` is truthy (a non-nil, non-false value), then returns the
  sole entry of `projects` directly if there is exactly one, otherwise
  prompts (`LinearCli.CLI.Prompt.select/2`) across all of `projects`.
  """
  def ask_for_projects(projects, search \\ nil)

  def ask_for_projects(projects, search) do
    if search, do: Prompt.warn("No project found matching #{search}.")

    case projects do
      [only] -> only
      _ -> Prompt.select("Project:", Enum.map(projects, &{&1.name, &1}))
    end
  end
end
