defmodule RepoTasks.Shell do
  @moduledoc """
  Runs an external command (a `mix release` inside `app/`, or one of the
  `ci/*.sh` scripts) with its output streamed live to stdout as it's
  produced, raising via `Mix.raise/1` on a non-zero exit - a clean error
  message and exit code, not a stacktrace, matching how every other Mix
  task failure in this codebase behaves.

  Every repo-management task built on top of this shells out rather than
  running anything in-process - see `RepoTasks.MixProject`'s own
  moduledoc for why.
  """

  @doc """
  Runs `cmd` with `args`, streaming combined stdout/stderr live.

  `opts` forwards to `System.cmd/3` (e.g. `cd:`, `env:`) - `:into` and
  `:stderr_to_stdout` are already set here and can't be overridden, since
  live streaming is this function's whole point.
  """
  @spec run!(String.t(), [String.t()], keyword()) :: :ok
  def run!(cmd, args, opts \\ []) do
    # System.cmd/3 only resolves a bare name (e.g. "mix") via PATH lookup -
    # a relative script path like "./ci/build_image.sh" isn't in PATH nor
    # absolute, so it raises :enoent (verified directly - this isn't a
    # shell, "./" isn't special to it the way it is to bash). Expand any
    # path-shaped cmd (contains "/") to absolute, relative to this
    # process's cwd; bare command names are left alone for PATH lookup.
    cmd = if String.contains?(cmd, "/"), do: Path.expand(cmd), else: cmd

    Mix.shell().info("+ #{cmd} #{Enum.join(args, " ")}")

    cmd_opts =
      opts
      |> Keyword.put(:into, IO.stream(:stdio, :line))
      |> Keyword.put(:stderr_to_stdout, true)

    {_io, status} = System.cmd(cmd, args, cmd_opts)

    if status != 0 do
      Mix.raise("#{cmd} #{Enum.join(args, " ")} exited with status #{status}")
    end

    :ok
  end
end
