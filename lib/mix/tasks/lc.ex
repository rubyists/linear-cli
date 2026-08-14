defmodule Mix.Tasks.Lc do
  @shortdoc "Runs this checkout's Linear CLI"

  @moduledoc """
  #{@shortdoc}.

      mix lc [LC_ARGS...]

  Proxies every argument to `LinearCli.CLI.main/1` in the sibling `app/`
  project. The child `mix run` compiles and starts the application when
  needed, so contributors can exercise the development checkout from the
  repository root with the same arguments they would give an installed
  `lc` binary:

      mix lc issue list
      mix lc whoami --output json

  Standard input, standard output, and standard error are inherited by the
  child, so interactive prompts work normally and the two output streams
  remain separate. The child CLI's exit status is preserved. Child Mix
  progress messages are suppressed so they do not corrupt `--output json`;
  diagnostics from `lc` itself are not suppressed.
  """

  use Mix.Task

  @entrypoint "LinearCli.CLI.main(System.argv())"

  @impl Mix.Task
  def run(argv) do
    run(argv, &run_child/3, &System.halt/1)
  end

  @doc false
  def run(argv, command, halt) do
    args = ["run", "-e", @entrypoint, "--" | argv]

    command_opts = [
      cd: Path.expand("app"),
      env: [{"MIX_QUIET", "1"}],
      stdio: :inherit
    ]

    status = command.("mix", args, command_opts)

    if status != 0 do
      halt.(status)
    end

    :ok
  end

  @doc false
  def run_child(executable, args, opts) do
    :inherit = Keyword.fetch!(opts, :stdio)

    executable =
      System.find_executable(executable) ||
        Mix.raise("could not find #{executable} on PATH")

    port =
      Port.open(
        {:spawn_executable, executable},
        [
          # Keep file descriptors 0, 1, and 2 attached to the caller. The
          # port uses its auxiliary descriptors only to report lifecycle
          # events, which preserves prompts and keeps stdout/stderr separate.
          :nouse_stdio,
          :exit_status,
          args: args,
          cd: Keyword.fetch!(opts, :cd),
          env: port_env(Keyword.fetch!(opts, :env))
        ]
      )

    receive do
      {^port, {:exit_status, status}} -> status
    end
  end

  defp port_env(environment) do
    Enum.map(environment, fn {name, value} ->
      {String.to_charlist(name), String.to_charlist(value)}
    end)
  end
end
