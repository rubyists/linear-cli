defmodule Mix.Tasks.Stokowski do
  @shortdoc "Validates this repo's workflow.yaml is safe for a Stokowski session"

  @moduledoc """
  #{@shortdoc}.

      mix stokowski

  Doesn't launch Stokowski itself yet - for now this just checks the
  root `workflow.yaml` is safe to use:

    * it exists
    * it's covered by `.gitignore` (it can hold a live Linear API key,
      so it must never be trackable)
    * its `tracker.api_key`, if set at all, is a `"$VAR"` env-var
      reference rather than a bare literal key (omitting the key
      entirely is also fine - Stokowski then falls back to the
      `LINEAR_API_KEY` env var directly)

  See `vendor/stokowski/README.md` for what the file needs to contain;
  actually starting a session is a follow-up step.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_argv) do
    workflow = Path.expand("workflow.yaml")

    unless File.exists?(workflow) do
      Mix.raise(
        "No workflow.yaml at #{workflow} - see vendor/stokowski/README.md's setup guide"
      )
    end

    unless gitignored?(workflow) do
      Mix.raise(
        "#{workflow} is not gitignored - it can hold a live Linear API key, add it to .gitignore before continuing"
      )
    end

    case api_key(workflow) do
      nil ->
        Mix.shell().info(
          "No tracker.api_key set - Stokowski will fall back to the LINEAR_API_KEY env var"
        )

      {:env_ref, var} ->
        Mix.shell().info("tracker.api_key references $#{var} - good")

      {:literal, _value} ->
        Mix.raise(
          "tracker.api_key in #{workflow} is a bare literal key - use \"$LINEAR_API_KEY\" (or omit the key entirely) instead"
        )
    end

    Mix.shell().info("#{workflow} looks safe to use.")
    :ok
  end

  defp gitignored?(path) do
    match?({_, 0}, System.cmd("git", ["check-ignore", "-q", path], stderr_to_stdout: true))
  end

  defp api_key(path) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r/^\s*api_key:\s*"?([^"\s#]+)/, line) do
        [_, "$" <> var] -> {:env_ref, var}
        [_, value] -> {:literal, value}
        nil -> nil
      end
    end)
  end
end
