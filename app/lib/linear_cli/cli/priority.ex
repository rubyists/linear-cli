defmodule LinearCli.CLI.Priority do
  @moduledoc """
  Shared priority name parser for `lc issue create` and `lc issue update`.

  Maps the canonical, case-insensitive friendly names (`none`, `urgent`,
  `high`, `medium`, `low`) to the integer values Linear's API expects
  (0–4, matching `IssueCreateInput.priority` and `IssueUpdateInput.priority`).
  """

  @priority_map %{
    "none" => 0,
    "urgent" => 1,
    "high" => 2,
    "medium" => 3,
    "low" => 4
  }

  @valid_values Map.keys(@priority_map) |> Enum.sort()

  @doc """
  Parses a priority name string into a Linear priority integer.

  Accepts `none`, `urgent`, `high`, `medium`, `low` (case-insensitive).
  Returns `{:ok, integer}` on success or `{:error, message}` for unknown values.
  """
  @spec parse(String.t()) :: {:ok, 0..4} | {:error, String.t()}
  def parse(value) when is_binary(value) do
    case Map.fetch(@priority_map, String.downcase(value)) do
      {:ok, int} ->
        {:ok, int}

      :error ->
        {:error,
         "unknown priority #{inspect(value)}; must be one of: #{Enum.join(@valid_values, ", ")}"}
    end
  end
end
