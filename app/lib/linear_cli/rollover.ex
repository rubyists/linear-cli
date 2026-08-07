defmodule LinearCli.Rollover do
  @moduledoc """
  Moves every open issue from last month's dated project to this month's
  dated project (e.g. `PAYMENTS SWAT August 2026` -> `PAYMENTS SWAT
  September 2026`), auto-creating the target project if it doesn't exist
  yet. New in Phase 7 - Ruby has no equivalent, see
  `documents/phase-7-plan.adoc`.

  Pure logic, no `Oban.Worker` behaviour - kept directly callable/testable,
  same "thin OTP boundary, pure logic underneath" split as
  `LinearCli.Git`/`LinearCli.CLI.IssueHelpers`. `LinearCli.Rollover.Worker`
  is the thin Oban wrapper that calls `run/2`.
  """

  alias LinearCli.Linear

  @month_names ~w(January February March April May June July August September October November December)

  @doc """
  Shifts `date` by `offset` months, returning the resulting `{year, month}`.
  Handles year rollover in either direction - `shift_month(~D[2026-01-15],
  -1) == {2025, 12}`. Elixir's `Date` module has no built-in month
  arithmetic (`Date.add/2` only shifts by days).
  """
  def shift_month(%Date{year: year, month: month}, offset) when is_integer(offset) do
    total = year * 12 + (month - 1) + offset
    {Integer.floor_div(total, 12), Integer.mod(total, 12) + 1}
  end

  @doc "e.g. month_name(8) == \"August\""
  def month_name(month) when month in 1..12, do: Enum.at(@month_names, month - 1)

  @doc "e.g. project_name(\"PAYMENTS SWAT\", {2026, 8}) == \"PAYMENTS SWAT August 2026\""
  def project_name(prefix, {year, month}), do: "#{prefix} #{month_name(month)} #{year}"

  @doc """
  Runs one rollover for `prefix`, computing last/this month's project names
  from `today`. If last month's project doesn't exist (e.g. the very first
  run), there's nothing to move - not an error. Otherwise finds (or creates)
  this month's project on the same team(s) and moves every open issue over
  concurrently, same `Task.async_stream` pattern as Phase 5.
  """
  def run(prefix, today \\ Date.utc_today()) do
    source_name = project_name(prefix, shift_month(today, -1))
    target_name = project_name(prefix, {today.year, today.month})

    with {:ok, source} <- find_optional(source_name) do
      case source do
        nil -> {:ok, %{source: nil, target: nil, moved: 0}}
        source -> roll(source, target_name)
      end
    end
  end

  defp roll(source, target_name) do
    with {:ok, team_id} <- source_team_id(source),
         {:ok, target} <- find_or_create_target(target_name, team_id),
         {:ok, issues} <- Linear.issues(%{mine: false, project_id: source.id}),
         {:ok, moved} <- move_all(issues, target.id) do
      {:ok, %{source: source, target: target, moved: moved}}
    end
  end

  defp source_team_id(%{teams: [%{id: id} | _]}), do: {:ok, id}
  defp source_team_id(source), do: {:error, {:no_team_for_project, source.id}}

  defp find_or_create_target(name, team_id) do
    with {:ok, nil} <- find_optional(name) do
      Linear.create_project(name, team_id)
    end
  end

  # Ash's get?: true "zero results" signal comes wrapped as
  # %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}, not a bare
  # NotFound - same shape LinearCli.CLI's own handle_error/3 matches on.
  defp find_optional(name) do
    case Linear.find_project_by_name(name) do
      {:ok, project} -> {:ok, project}
      {:error, %Ash.Error.Invalid{errors: [%Ash.Error.Query.NotFound{} | _]}} -> {:ok, nil}
      {:error, reason} -> {:error, reason}
    end
  end

  defp move_all(issues, target_id) do
    issues
    |> Task.async_stream(&Linear.attach_issue_to_project(&1, target_id), timeout: 30_000)
    |> Enum.reduce_while({:ok, 0}, fn
      {:ok, {:ok, _issue}}, {:ok, count} -> {:cont, {:ok, count + 1}}
      {:ok, {:error, reason}}, {:ok, _count} -> {:halt, {:error, reason}}
      {:exit, reason}, {:ok, _count} -> {:halt, {:error, {:task_exit, reason}}}
    end)
  end
end
