defmodule Mix.Tasks.Burrito.Dinein do
  @shortdoc "Builds a local Burrito lc binary for the current host platform"

  @moduledoc """
  #{@shortdoc}.

      mix burrito.dinein [--target TARGET]

  Detects the current host platform, builds `app/`'s Burrito binary for that
  single target only (`MIX_ENV=prod BURRITO_TARGET=<target> mix release lc
  --overwrite`), then installs it as `app/burrito_out/lc` (dropping the
  target suffix) so it's immediately runnable as `./app/burrito_out/lc`.

  Supported targets (auto-detected from the current host):
  - `macos_aarch64` — macOS Apple Silicon
  - `linux_x86_64` — Linux x86_64
  - `windows_x86_64` — Windows x86_64

  Pass `--target TARGET` (`-t`) to override detection — useful for explicit
  cross-compilation when Zig can produce the target from this host.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @supported_targets ~w[macos_aarch64 linux_x86_64 windows_x86_64]

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      OptionParser.parse!(argv, strict: [target: :string], aliases: [t: :target])

    unless args == [] do
      Mix.raise("Usage: mix burrito.dinein [--target TARGET]")
    end

    target = opts[:target] || detect_target!()

    Mix.shell().info("==> Fetching app/ deps")
    Shell.run!("mix", ["deps.get"], cd: "app")

    Mix.shell().info("==> Building Burrito binary for #{target}")

    Shell.run!(
      "mix",
      ["release", "lc", "--overwrite"],
      cd: "app",
      env: [{"MIX_ENV", "prod"}, {"BURRITO_TARGET", target}]
    )

    # Burrito names output lc_<target> (lc_<target>.exe on Windows).
    # Rename to plain lc (lc.exe) so it's immediately usable without knowing
    # the target suffix.
    ext = if target == "windows_x86_64", do: ".exe", else: ""
    src = Path.join("app/burrito_out", "lc_#{target}#{ext}")
    dst = Path.join("app/burrito_out", "lc#{ext}")

    case File.rename(src, dst) do
      :ok ->
        Mix.shell().info("==> Built: #{dst}")

      {:error, reason} ->
        Mix.raise("Failed to install #{src} as #{dst}: #{:file.format_error(reason)}")
    end

    :ok
  end

  @doc """
  Returns the Burrito target name matching the current host platform.

  Raises `Mix.Error` with an actionable message on unsupported platforms.
  """
  @spec detect_target!() :: String.t()
  def detect_target! do
    os = detect_os()
    cpu = detect_cpu()

    case {os, cpu} do
      {:darwin, :aarch64} ->
        "macos_aarch64"

      {:linux, :x86_64} ->
        "linux_x86_64"

      {:windows, :x86_64} ->
        "windows_x86_64"

      {os, cpu} ->
        Mix.raise(
          "Unsupported platform: #{os}/#{cpu}. " <>
            "Supported targets: #{Enum.join(@supported_targets, ", ")}"
        )
    end
  end

  defp detect_os do
    case :os.type() do
      {:win32, _} -> :windows
      {:unix, :darwin} -> :darwin
      {:unix, :linux} -> :linux
    end
  end

  defp detect_cpu do
    arch =
      :erlang.system_info(:system_architecture)
      |> to_string()
      |> String.downcase()
      |> String.split("-")
      |> List.first()

    case arch do
      "x86_64" -> :x86_64
      "aarch64" -> :aarch64
      "arm64" -> :aarch64
      other -> String.to_atom(other)
    end
  end
end
