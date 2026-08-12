defmodule Mix.Tasks.Container.Publish do
  @shortdoc "Publishes an already-built local container image to the registry"

  @moduledoc """
  #{@shortdoc}.

      mix container.publish TAG

  Thin wrapper around `ci/publish.sh` - the image must already be built
  locally under the same TAG (`mix container.build TAG`, or
  `ci/build_image.sh` directly). Needs `REGISTRY_TOKEN` or `GITHUB_TOKEN`
  set to log in to the registry - `ci/publish.sh`'s own requirement,
  unchanged here.
  """

  use Mix.Task

  alias RepoTasks.Shell

  @impl Mix.Task
  def run(argv) do
    case argv do
      [tag] ->
        Mix.shell().info("==> Publishing #{tag}")
        Shell.run!("./ci/publish.sh", [tag])
        :ok

      _ ->
        Mix.raise("Usage: mix container.publish TAG")
    end
  end
end
