defmodule Mix.Tasks.Stokowski do
  @shortdoc "Starts a Stokowski agent-orchestration session against this repo's workflow.yaml"

  @moduledoc """
  #{@shortdoc}.

      mix stokowski [--dry-run] [--port PORT] [--host HOST] [-v]

  Checks the root `workflow.yaml` is safe (see below), then runs it via
  `uv run --project vendor/stokowski`. `--with-editable` is required
  alongside `--project` - `vendor/stokowski`'s `pyproject.toml` has no
  `[build-system]` table, so a plain `uv run --project` only syncs its
  dependencies, never installs the `stokowski` package/entry point
  itself (confirmed directly - `uv run` without `--with-editable` fails
  with "Failed to spawn: `stokowski`" even though the venv builds
  cleanly). Fixing that upstream is a separate, future PR; this works
  around it locally in the meantime. Any flags given are passed straight
  through to `stokowski` itself; see `vendor/stokowski/README.md` for
  what each does.

  Safety checks before launching:

    * `workflow.yaml` exists
    * its `tracker.api_key`, if set at all, is a `"$VAR"` env-var
      reference rather than a bare literal key (omitting the key
      entirely is also fine - Stokowski then falls back to the
      `LINEAR_API_KEY` env var directly)

  `workflow.yaml` is meant to be tracked in this repo, not gitignored -
  this is a best-effort guard against a literal API key ever landing in
  it, not a requirement that the file stay untracked. This task never
  reads, passes, or logs that key itself - Stokowski resolves it on its
  own and `uv run` inherits this process's environment unmodified.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    workflow = Path.expand("workflow.yaml")

    unless File.exists?(workflow) do
      Mix.raise("No workflow.yaml at #{workflow} - see vendor/stokowski/README.md's setup guide")
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

    Shell.run!(
      "uv",
      [
        "run",
        "--project",
        "vendor/stokowski",
        "--extra",
        "web",
        "--with-editable",
        "vendor/stokowski",
        "--",
        "stokowski",
        workflow
      ] ++ argv
    )

    :ok
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
