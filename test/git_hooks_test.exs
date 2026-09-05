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

  test "the shared subject guard rejects the squash title from pull request 196" do
    title = "EXT-19: isolate Burrito musl loader per user (#196)"

    assert {output, 1} = run(@subject_guard, ["--subject", title])
    assert output =~ "Commit subject must use Conventional Commits format"
  end

  test "the shared subject guard accepts a commit message file with body and footer" do
    path =
      write_commit_msg!(
        "feat(ci): add range validation\n\nBody.\n\nCo-authored-by: X <x@example.com>\n"
      )

    assert {"", 0} = run(@subject_guard, [path])
  end

  test "the shared subject guard skips comment lines in a commit message file" do
    path = write_commit_msg!("# This is a comment\n\nfeat: valid subject after comment lines\n")
    assert {"", 0} = run(@subject_guard, [path])
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

  test "the pull request guard rejects a missing required title" do
    env = [{"PULL_REQUEST_TITLE_REQUIRED", "true"}]

    assert {output, 1} = run(@title_guard, [], env: env)
    assert output =~ "PULL_REQUEST_TITLE must be set"
  end

  test "the shared subject guard rejects an empty subject" do
    assert {output, 1} = run(@subject_guard, ["--subject", ""])
    assert output =~ "Commit subject is empty"
  end

  test "the pull request guard rejects an invalid PULL_REQUEST_TITLE_REQUIRED value" do
    env = [{"PULL_REQUEST_TITLE_REQUIRED", "maybe"}]

    assert {output, 1} = run(@title_guard, [], env: env)
    assert output =~ "PULL_REQUEST_TITLE_REQUIRED must be"
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
    {worktree, hooks_dir} = setup_hooks_worktree!()
    {initial_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    initial_sha = String.trim(initial_sha)

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

  test "the range guard passes when the commit range is empty" do
    {worktree, hooks_dir} = setup_hooks_worktree!()
    assert {"", 0} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
  end

  test "the range guard reports all invalid subjects in a mixed commit range" do
    {worktree, hooks_dir} = setup_hooks_worktree!()

    File.write!(Path.join(worktree, "a"), "a")
    git!(worktree, ["add", "a"])
    git!(worktree, ["commit", "-m", "feat: valid commit"])

    File.write!(Path.join(worktree, "b"), "b")
    git!(worktree, ["add", "b"])
    git!(worktree, ["commit", "-m", "not conventional at all"])

    File.write!(Path.join(worktree, "c"), "c")
    git!(worktree, ["add", "c"])
    git!(worktree, ["commit", "-m", "also bad subject"])

    assert {output, 1} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
    assert output =~ "not conventional at all"
    assert output =~ "also bad subject"
    refute output =~ "feat: valid commit"
  end

  test "the range guard skips a GitHub Update-branch merge commit matching all three predicates" do
    {worktree, hooks_dir} = setup_hooks_worktree!()
    add_github_merge!(worktree)

    assert {"", 0} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
  end

  test "the range guard validates when the committer name is not GitHub" do
    {worktree, hooks_dir} = setup_hooks_worktree!()
    add_github_merge!(worktree, committer_name: "Not GitHub")

    assert {output, 1} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates when the committer email is not noreply@github.com" do
    {worktree, hooks_dir} = setup_hooks_worktree!()
    add_github_merge!(worktree, committer_email: "not@github.com")

    assert {output, 1} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates a single-parent commit whose subject matches the GitHub pattern" do
    {worktree, hooks_dir} = setup_hooks_worktree!()

    git!(worktree, ["commit", "--allow-empty", "-m", "Merge branch 'main' into feature"])

    assert {output, 1} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates a two-parent GitHub-committer merge with a non-matching subject" do
    {worktree, hooks_dir} = setup_hooks_worktree!()
    add_github_merge!(worktree, subject: "Merge feature into main")

    assert {output, 1} = run(Path.join(hooks_dir, "validate-commit-range"), [], cd: worktree)
    assert output =~ "Merge feature into main"
  end

  # Creates a no-fast-forward merge commit on `main` from a throwaway `feature`
  # branch. Defaults simulate GitHub's "Update branch" committer identity and
  # subject so the predicate in validate-commit-range matches.
  defp add_github_merge!(worktree, opts \\ []) do
    committer_name = Keyword.get(opts, :committer_name, "GitHub")
    committer_email = Keyword.get(opts, :committer_email, "noreply@github.com")
    subject = Keyword.get(opts, :subject, "Merge branch 'main' into feature")

    git!(worktree, ["checkout", "-b", "feature"])
    File.write!(Path.join(worktree, "feature_file"), "feature content")
    git!(worktree, ["add", "feature_file"])
    git!(worktree, ["commit", "-m", "feat: add feature"])
    git!(worktree, ["checkout", "main"])

    git_with_env!(worktree, ["merge", "--no-ff", "-m", subject, "feature"], [
      {"GIT_COMMITTER_NAME", committer_name},
      {"GIT_COMMITTER_EMAIL", committer_email}
    ])
  end

  defp git_with_env!(directory, args, extra_env) do
    case System.cmd("git", args, cd: directory, stderr_to_stdout: true, env: extra_env) do
      {_output, 0} ->
        :ok

      {output, status} ->
        flunk("git #{Enum.join(args, " ")} failed (#{status}):\n#{output}")
    end
  end

  # Creates a git repo in a temp dir with origin set up and the guard scripts
  # copied in. Uses a cryptographic nonce so collisions cannot occur across
  # BEAM VM restarts (unlike System.unique_integer/1 which resets each run).
  defp setup_hooks_worktree! do
    test_root = tmp_dir!("root")
    bare_repo = Path.join(test_root, "origin.git")
    worktree = Path.join(test_root, "worktree")
    File.mkdir!(worktree)

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

    hooks_dir = Path.join(worktree, "git-hooks")
    File.mkdir_p!(hooks_dir)

    for guard <- [@subject_guard, @range_guard] do
      destination = Path.join(hooks_dir, Path.basename(guard))
      File.cp!(guard, destination)
      File.chmod!(destination, 0o755)
    end

    {worktree, hooks_dir}
  end

  defp write_commit_msg!(content) do
    nonce = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "linear_cli_git_hooks_commit_msg_#{nonce}")
    File.write!(path, content)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp tmp_dir!(prefix) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "linear_cli_git_hooks_#{prefix}_#{nonce}")
    File.mkdir!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
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
