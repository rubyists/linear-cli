defmodule LinearCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :linear_cli,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      consolidate_protocols: Mix.env() != :dev,
      usage_rules: usage_rules(),
      escript: escript()
    ]
  end

  defp escript do
    [main_module: LinearCli.CLI]
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
      {:sourceror, "~> 1.8", only: [:dev, :test]},
      {:ash, "~> 3.0"},
      {:igniter, "~> 0.6", only: [:dev, :test]}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end
end
