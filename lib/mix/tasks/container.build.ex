defmodule Mix.Tasks.Container.Build do
  @shortdoc "Builds the linux_x86_64 Burrito binary, then the container image"

  @moduledoc """
  #{@shortdoc}.

      mix container.build TAG [--push]

  Builds `app/`'s `linux_x86_64` Burrito binary (the container's payload -
  `MIX_ENV=prod BURRITO_TARGET=linux_x86_64 mix release lc --overwrite` -
  `--overwrite` so re-running this locally for a version already built
  doesn't block on `mix release`'s own interactive prompt), then the
  container image itself via `ci/build_image.sh`. With `--push` (`-p`),
  chains straight into `mix container.publish TAG` afterward.

  This is the exact flow `.github/workflows/main.yaml`'s `container` job
  runs - CI and a local `mix container.build v1.2.3 --push` do the
  identical thing, so there's one place to fix if either ever breaks.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    {opts, args} =
      OptionParser.parse!(argv, strict: [push: :boolean], aliases: [p: :push])

    tag =
      case args do
        [tag] -> tag
        _ -> Mix.raise("Usage: mix container.build TAG [--push]")
      end

    Mix.shell().info("==> Fetching app/ deps")
    Shell.run!("mix", ["deps.get"], cd: "app")

    Mix.shell().info("==> Building the linux_x86_64 Burrito binary")

    Shell.run!(
      "mix",
      ["release", "lc", "--overwrite"],
      cd: "app",
      env: [{"MIX_ENV", "prod"}, {"BURRITO_TARGET", "linux_x86_64"}]
    )

    Mix.shell().info("==> Building the container image (#{tag})")
    Shell.run!("./ci/build_image.sh", [tag], env: [{"APP_VERSION", tag}])

    if opts[:push] do
      Mix.Task.run("container.publish", [tag])
    end

    :ok
  end
end
