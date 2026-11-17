defmodule LinearCli.GitTest do
  use ExUnit.Case, async: true

  alias LinearCli.Git

  # Every test gets a fresh local repo (with one commit on "main") plus a
  # fresh bare "origin" it's already pushed/tracking main against - all
  # under System.tmp_dir!(), never against the real project working
  # directory. See house rule 6 in the project instructions.
  setup do
    origin_path = tmp_dir!("origin")
    {_output, 0} = System.cmd("git", ["init", "--bare", "-q"], cd: origin_path)

    # `git init --bare`'s HEAD symref follows the runner's ambient
    # init.defaultBranch config (falling back to git's legacy "master" if
    # unset) - since this repo only ever gets a "main" branch pushed to it,
    # that can leave HEAD dangling at a "master" that never exists, and
    # `git ls-remote --symref` then reports nothing for it. Set it explicitly
    # (the same thing a real git host does when you configure a repo's
    # default branch) so this doesn't depend on the runner's global config -
    # this is what made `default_branch/0`'s test pass locally but fail in CI.
    {_output, 0} =
      System.cmd("git", ["symbolic-ref", "HEAD", "refs/heads/main"], cd: origin_path)

    repo_path = tmp_dir!("repo")
    init_repo!(repo_path)
    commit_file!(repo_path, "README.md", "hello")
    {_output, 0} = System.cmd("git", ["branch", "-M", "main"], cd: repo_path)
    {_output, 0} = System.cmd("git", ["remote", "add", "origin", origin_path], cd: repo_path)
    {_output, 0} = System.cmd("git", ["push", "-q", "-u", "origin", "main"], cd: repo_path)

    %{repo: repo_path, origin: origin_path}
  end

  # `System.unique_integer/1` is unique only within the current BEAM VM. A
  # fresh `mix test` process starts its sequence over, so an interrupted prior
  # run can otherwise reuse its stale /tmp fixture. A cryptographic nonce makes
  # the directory unique across processes as well; register cleanup before any
  # Git command can fail, so failed setup does not leave another collision
  # behind.
  defp tmp_dir!(prefix) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "linear_cli_git_test_#{prefix}_#{nonce}")

    File.mkdir!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end

  defp init_repo!(path) do
    {_output, 0} = System.cmd("git", ["init", "-q"], cd: path)
    {_output, 0} = System.cmd("git", ["config", "user.name", "Test User"], cd: path)
    {_output, 0} = System.cmd("git", ["config", "user.email", "test@example.com"], cd: path)
  end

  defp commit_file!(path, filename, contents) do
    File.write!(Path.join(path, filename), contents)
    {_output, 0} = System.cmd("git", ["add", filename], cd: path)
    {_output, 0} = System.cmd("git", ["commit", "-q", "-m", "commit #{filename}"], cd: path)
  end

  describe "current_branch/0" do
    test "returns the currently checked out branch name", %{repo: repo} do
      assert Git.current_branch(cwd: repo) == {:ok, "main"}
    end
  end

  describe "checkout_branch/1" do
    test "creates and checks out a new local branch when it doesn't exist yet", %{repo: repo} do
      assert Git.checkout_branch("feature/new-thing", cwd: repo) == {:ok, "feature/new-thing"}
      assert Git.current_branch(cwd: repo) == {:ok, "feature/new-thing"}
    end

    test "checks out an already-existing local branch instead of recreating it", %{repo: repo} do
      assert Git.checkout_branch("feature/existing", cwd: repo) == {:ok, "feature/existing"}
      assert Git.checkout_branch("main", cwd: repo) == {:ok, "main"}

      assert Git.checkout_branch("feature/existing", cwd: repo) == {:ok, "feature/existing"}
      assert Git.current_branch(cwd: repo) == {:ok, "feature/existing"}
    end

    test "returns an error tuple for an invalid branch name", %{repo: repo} do
      assert {:error, _reason} = Git.checkout_branch("..", cwd: repo)
    end
  end

  describe "pull_or_push_new_branch!/1" do
    test "pulls when the current branch already tracks an upstream", %{repo: repo} do
      assert {:ok, {:pulled, _output}} = Git.pull_or_push_new_branch!("main", cwd: repo)
    end

    test "pushes to origin and sets upstream when there is no tracking branch yet", %{
      repo: repo
    } do
      assert Git.checkout_branch("feature/no-upstream", cwd: repo) == {:ok, "feature/no-upstream"}

      assert Git.pull_or_push_new_branch!("feature/no-upstream", cwd: repo) ==
               {:ok, {:pushed_new_branch, "feature/no-upstream"}}

      assert {upstream_output, 0} =
               System.cmd(
                 "git",
                 ["rev-parse", "--abbrev-ref", "feature/no-upstream@{upstream}"],
                 cd: repo
               )

      assert String.trim(upstream_output) == "origin/feature/no-upstream"
    end
  end

  describe "default_branch/0" do
    test "returns the remote's default branch", %{repo: repo} do
      assert Git.default_branch(cwd: repo) == {:ok, "main"}
    end

    test "returns an error tuple when there is no origin remote" do
      repo_path = tmp_dir!("repo_no_origin")
      init_repo!(repo_path)
      commit_file!(repo_path, "README.md", "hello")

      assert {:error, _reason} = Git.default_branch(cwd: repo_path)
    end
  end
end
