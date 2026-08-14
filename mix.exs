defmodule RepoTasks.MixProject do
  use Mix.Project

  # Repo-management tasks (mix container.build/publish, and more to come) -
  # deliberately its own Mix project, sibling to app/, not nested inside it.
  # app/ is the CLI itself; this is tooling that operates ON the repo as a
  # whole (this file's own directory, plus ci/, oci/, .github/workflows/ -
  # things app/'s own mix.exs has no business knowing about). Kept
  # dependency-free on purpose: every task here just orchestrates other
  # already-existing tools (mix release inside app/, the ci/*.sh scripts)
  # as child OS processes, never runs them in-process.
  def project do
    [
      app: :repo_tasks,
      version: "0.1.0",
      elixir: "~> 1.20",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    []
  end
end
