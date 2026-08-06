defmodule Mix.Tasks.Vendor.Sync do
  @moduledoc "Checks out each vendor/ submodule to the tag matching its resolved version in mix.lock."
  @shortdoc "Syncs vendor/ submodules to the versions resolved in mix.lock"

  use Mix.Task

  @vendor_map %{
    ash: "../vendor/ash",
    oban: "../vendor/oban",
    usage_rules: "../vendor/usage_rules",
    optimus: "../vendor/optimus",
    owl: "../vendor/owl",
    marcli: "../vendor/marcli"
  }

  @impl Mix.Task
  def run(_args) do
    lock = Mix.Dep.Lock.read()

    Enum.each(@vendor_map, fn {package, path} ->
      case version_for(lock, package) do
        nil ->
          Mix.shell().info("warning: #{package} not found in mix.lock, skipping")

        version ->
          sync(package, path, version)
      end
    end)
  end

  defp version_for(lock, package) do
    case Map.get(lock, package) do
      {:hex, _name, version, _inner_checksum, _managers, _deps, _repo, _outer_checksum} ->
        version

      _ ->
        nil
    end
  end

  defp sync(package, path, version) do
    if File.dir?(path) do
      tag = "v#{version}"

      System.cmd("git", ["-C", path, "fetch", "--tags"])

      case System.cmd("git", ["-C", path, "checkout", tag], stderr_to_stdout: true) do
        {_output, 0} ->
          Mix.shell().info("#{package}: checked out #{tag}")

        {output, _status} ->
          Mix.shell().info(
            "warning: #{package}: could not check out #{tag} (#{String.trim(output)})"
          )
      end
    else
      Mix.shell().info("warning: #{package}: vendor path #{path} does not exist, skipping")
    end
  end
end
