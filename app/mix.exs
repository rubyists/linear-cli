defmodule LinearCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :linear_cli,
      # x-release-please-start-version
      version: "0.8.5",
      # x-release-please-end
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      usage_rules: usage_rules(),
      escript: escript(),
      releases: releases()
    ]
  end

  defp escript do
    [main_module: LinearCli.CLI, name: "lc"]
  end

  # Burrito-wrapped release, both the interactive CLI and (with
  # LINEAR_CLI_DAEMON=true) the daemon - one binary, not two build
  # artifacts. Targets and their host-compatibility verified against
  # Burrito's own docs/source, and exqlite's NIF cross-compilation verified
  # empirically (built+ran the linux_x86_64 target under podman/QEMU) - see
  # documents/phase-8-plan.adoc. macOS Intel intentionally not targeted.
  defp releases do
    [
      lc: [
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          targets: [
            macos_aarch64: [os: :darwin, cpu: :aarch64],
            linux_x86_64: [os: :linux, cpu: :x86_64],
            windows_x86_64: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp usage_rules do
    [
      file: "../AGENTS.md",
      usage_rules: [:ash, ~r/^ash_/, {:oban, sub_rules: []}]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {LinearCli.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:marcli, "~> 0.3"},
      {:owl, "~> 0.13"},
      {:optimus, "~> 0.6"},
      {:req, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:plug, "~> 1.0", only: :test},
      {:usage_rules, "~> 1.2", only: [:dev]},
      {:oban, "~> 2.23"},
      {:ecto_sqlite3, "~> 0.9"},
      {:postgrex, "~> 0.22"},
      {:burrito, "~> 1.6"},
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]},
      {:sbom, "~> 0.10", only: :dev, runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
