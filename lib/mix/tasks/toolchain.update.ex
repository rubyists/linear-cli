defmodule Mix.Tasks.Toolchain.Update do
  @shortdoc "Updates the Claude Code and Codex pins in mise.toml"

  @moduledoc """
  #{@shortdoc}.

      mix toolchain.update

  Gets the latest npm versions for Claude Code and Codex.
  Then updates their pins in `mise.toml`.
  """

  use Mix.Task

  @tools [
    {"claude", "@anthropic-ai/claude-code"},
    {"codex", "@openai/codex"}
  ]

  @npm_registry "https://registry.npmjs.org"

  @impl Mix.Task
  def run([]) do
    update("mise.toml")
  end

  def run(_argv), do: Mix.raise("Usage: mix toolchain.update")

  @doc false
  def update(mise_path) do
    start_req!()
    versions = Enum.map(@tools, fn {tool, package} -> {tool, npm_version!(package)} end)
    mise_toml = File.read!(mise_path)

    File.write!(mise_path, update_versions!(mise_toml, versions))

    Mix.shell().info("Updated Claude Code and Codex pins in #{mise_path}")
  end

  @doc false
  def update_versions!(mise_toml, versions) do
    Enum.reduce(versions, mise_toml, fn {tool, version}, contents ->
      pattern = ~r/^#{Regex.escape(tool)}\s*=\s*"[^"]+"$/m

      if Regex.match?(pattern, contents) do
        Regex.replace(pattern, contents, "#{tool} = \"#{version}\"")
      else
        Mix.raise("mise.toml does not pin #{tool}")
      end
    end)
  end

  defp npm_version!(package) do
    case Req.get(request_options(package)) do
      {:ok, %Req.Response{status: 200, body: %{"latest" => version}}} when is_binary(version) ->
        version

      {:ok, %Req.Response{status: 200}} ->
        Mix.raise("npm registry response for #{package} does not include a latest version")

      {:ok, %Req.Response{status: status}} ->
        Mix.raise("npm registry request for #{package} exited with status #{status}")

      {:error, exception} ->
        Mix.raise("npm registry request for #{package} failed: #{Exception.message(exception)}")
    end
  end

  defp request_options(package) do
    [url: "#{@npm_registry}/-/package/#{URI.encode(package, &URI.char_unreserved?/1)}/dist-tags"]
    |> Keyword.merge(Application.get_env(:repo_tasks, :npm_req_options, []))
  end

  defp start_req! do
    case Application.ensure_all_started(:req) do
      {:ok, _started} -> :ok
      {:error, reason} -> Mix.raise("Cannot start Req: #{inspect(reason)}")
    end
  end
end
