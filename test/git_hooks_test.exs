defmodule GitHooksTest do
  use ExUnit.Case, async: true

  @subject_guard Path.expand("../git-hooks/validate-conventional-subject", __DIR__)
  @title_guard Path.expand("../git-hooks/validate-pull-request-title", __DIR__)
  @range_guard Path.expand("../git-hooks/validate-commit-range", __DIR__)

  test "the shared subject guard accepts Conventional Commits" do
    assert {"", 0} = run(@subject_guard, ["--subject", "feat(api): add title validation"])
  end

  test "the shared subject guard rejects the squash title from pull request 197" do
    title = "Stokowski tooling: fix Claude→Qwen routing, add lc issue comment (#197)"

    assert {output, 1} = run(@subject_guard, ["--subject", title])
    assert output =~ "Commit subject must use Conventional Commits format"
  end

  test "the pull request guard accepts a valid required title" do
    env = [
      {"PULL_REQUEST_TITLE_REQUIRED", "true"},
      {"PULL_REQUEST_TITLE", "feat(ci): enforce pull request titles"}
    ]

    assert {output, 0} = run(@title_guard, [], env: env)
    assert output =~ "Pull request title uses Conventional Commits format"
  end

  test "the pull request guard rejects an invalid required title" do
    env = [
      {"PULL_REQUEST_TITLE_REQUIRED", "true"},
      {"PULL_REQUEST_TITLE", "EXT-17: isolate Burrito musl loader per user"}
    ]

    assert {output, 1} = run(@title_guard, [], env: env)
    assert output =~ "Pull request title must use Conventional Commits format"
  end

  test "the pull request guard skips non-pull-request events" do
    env = [
      {"PULL_REQUEST_TITLE_REQUIRED", "false"},
      {"PULL_REQUEST_TITLE", "not conventional"}
    ]

    assert {output, 0} = run(@title_guard, [], env: env)
    assert output =~ "Skipping pull request title validation"
  end

  test "the range guard compares local main against origin/main" do
    test_root =
      Path.join(System.tmp_dir!(), "linear_cli_git_hooks_#{System.unique_integer([:positive])}")

    bare_repo = Path.join(test_root, "origin.git")
    worktree = Path.join(test_root, "worktree")

    on_exit(fn -> File.rm_rf!(test_root) end)

    File.mkdir_p!(worktree)
    git!(test_root, ["init", "--bare", bare_repo])
    git!(worktree, ["init", "--initial-branch", "main"])
    git!(worktree, ["config", "user.name", "Git Hooks Test"])
    git!(worktree, ["config", "user.email", "git-hooks@example.com"])
    git!(worktree, ["config", "commit.gpgsign", "false"])

    File.write!(Path.join(worktree, "README"), "initial\n")
    git!(worktree, ["add", "README"])
    git!(worktree, ["commit", "-m", "chore: create test repository"])
    git!(worktree, ["remote", "add", "origin", bare_repo])
    git!(worktree, ["push", "--set-upstream", "origin", "main"])
    {initial_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    initial_sha = String.trim(initial_sha)

    hooks_dir = Path.join(worktree, "git-hooks")
    File.mkdir_p!(hooks_dir)

    for guard <- [@subject_guard, @range_guard] do
      destination = Path.join(hooks_dir, Path.basename(guard))
      File.cp!(guard, destination)
      File.chmod!(destination, 0o755)
    end

    File.write!(Path.join(worktree, "README"), "bad commit\n", [:append])
    git!(worktree, ["add", "README"])
    git!(worktree, ["commit", "-m", "this is not conventional"])

    assert {output, 1} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
    assert output =~ "this is not conventional"

    assert {output, 1} =
             run(Path.join(hooks_dir, "validate-commit-range"), [],
               cd: worktree,
               env: [{"BASE_REF", initial_sha}]
             )

    assert output =~ "this is not conventional"
  end

  defp run(command, args, opts \\ []) do
    opts = Keyword.put(opts, :stderr_to_stdout, true)
    System.cmd(command, args, opts)
  end

  defp git!(directory, args) do
    case System.cmd("git", args, cd: directory, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, status} -> flunk("git #{Enum.join(args, " ")} failed (#{status}):\n#{output}")
    end
  end
end
