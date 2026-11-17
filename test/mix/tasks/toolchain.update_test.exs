defmodule Mix.Tasks.Toolchain.UpdateTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Toolchain.Update

  setup do
    previous_options = Application.get_env(:repo_tasks, :npm_req_options)

    Application.put_env(:repo_tasks, :npm_req_options,
      plug: {Req.Test, __MODULE__},
      retry: false
    )

    on_exit(fn ->
      if previous_options do
        Application.put_env(:repo_tasks, :npm_req_options, previous_options)
      else
        Application.delete_env(:repo_tasks, :npm_req_options)
      end
    end)
  end

  test "gets each package version from the npm registry" do
    versions = %{
      "/-/package/%40anthropic-ai%2Fclaude-code/dist-tags" => "claude-test-version",
      "/-/package/%40openai%2Fcodex/dist-tags" => "codex-test-version"
    }

    Req.Test.stub(__MODULE__, fn conn ->
      version = Map.fetch!(versions, conn.request_path)
      Req.Test.json(conn, %{"latest" => version})
    end)

    mise_path =
      Path.join(System.tmp_dir!(), "toolchain-update-#{System.unique_integer([:positive])}.toml")

    File.write!(mise_path, "[tools]\ncodex = \"old\"\nclaude = \"old\"\n")

    on_exit(fn -> File.rm(mise_path) end)

    assert :ok = Update.update(mise_path)

    codex_version = Map.fetch!(versions, "/-/package/%40openai%2Fcodex/dist-tags")
    claude_version = Map.fetch!(versions, "/-/package/%40anthropic-ai%2Fclaude-code/dist-tags")

    assert File.read!(mise_path) ==
             "[tools]\ncodex = \"#{codex_version}\"\nclaude = \"#{claude_version}\"\n"
  end

  test "requires every tool to have a pin" do
    assert_raise Mix.Error, "mise.toml does not pin codex", fn ->
      Update.update_versions!(~s([tools]\nclaude = "placeholder"\n), [{"codex", "placeholder"}])
    end
  end
end
