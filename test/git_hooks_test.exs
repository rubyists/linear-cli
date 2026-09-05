defmodule GitHooksTest do
  use ExUnit.Case, async: true

  @subject_guard Path.expand("../ci/validate_conventional_subject.sh", __DIR__)
  @title_guard Path.expand("../ci/validate_pull_request_title.sh", __DIR__)
  @range_guard Path.expand("../ci/validate_commit_range.sh", __DIR__)
  @push_refs_guard Path.expand("../ci/validate_push_refs.sh", __DIR__)

  @zero_sha "0000000000000000000000000000000000000000"

  test "the shared subject guard accepts Conventional Commits" do
    assert {"", 0} = run(@subject_guard, ["--subject", "feat(api): add title validation"])
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
    {worktree, _} = setup_ci_worktree!()
    {initial_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    initial_sha = String.trim(initial_sha)

    File.write!(Path.join(worktree, "README"), "bad commit\n", [:append])
    git!(worktree, ["add", "README"])
    git!(worktree, ["commit", "-m", "this is not conventional"])

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "this is not conventional"

    assert {output, 1} =
             run(@range_guard, [],
               cd: worktree,
               env: [{"BASE_REF", initial_sha}]
             )

    assert output =~ "this is not conventional"
  end

  test "the range guard passes when the commit range is empty" do
    {worktree, _} = setup_ci_worktree!()
    assert {"", 0} = run(@range_guard, [], cd: worktree)
  end

  test "the range guard fetches a missing local default base from origin" do
    {worktree, _} = setup_ci_worktree!()

    # Mimic a shallow CI checkout: the remote has main, while neither a local
    # main branch nor origin/main is available to resolve without a fetch.
    git!(worktree, ["branch", "-m", "main", "feature"])
    git!(worktree, ["update-ref", "-d", "refs/remotes/origin/main"])

    File.write!(Path.join(worktree, "README"), "bad commit\n", [:append])
    git!(worktree, ["add", "README"])
    git!(worktree, ["commit", "-m", "this is not conventional"])

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "this is not conventional"
  end

  test "the range guard reports all invalid subjects in a mixed commit range" do
    {worktree, _} = setup_ci_worktree!()

    File.write!(Path.join(worktree, "a"), "a")
    git!(worktree, ["add", "a"])
    git!(worktree, ["commit", "-m", "feat: valid commit"])

    File.write!(Path.join(worktree, "b"), "b")
    git!(worktree, ["add", "b"])
    git!(worktree, ["commit", "-m", "not conventional at all"])

    File.write!(Path.join(worktree, "c"), "c")
    git!(worktree, ["add", "c"])
    git!(worktree, ["commit", "-m", "also bad subject"])

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "not conventional at all"
    assert output =~ "also bad subject"
    refute output =~ "feat: valid commit"
  end

  test "the range guard validates a GitHub Update-branch merge commit" do
    {worktree, _} = setup_ci_worktree!()
    add_github_merge!(worktree)

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates when the committer name is not GitHub" do
    {worktree, _} = setup_ci_worktree!()
    add_github_merge!(worktree, committer_name: "Not GitHub")

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates when the committer email is not noreply@github.com" do
    {worktree, _} = setup_ci_worktree!()
    add_github_merge!(worktree, committer_email: "not@github.com")

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates a single-parent commit whose subject matches the GitHub pattern" do
    {worktree, _} = setup_ci_worktree!()

    git!(worktree, ["commit", "--allow-empty", "-m", "Merge branch 'main' into feature"])

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "Merge branch 'main' into feature"
  end

  test "the range guard validates a two-parent GitHub-committer merge with a non-matching subject" do
    {worktree, _} = setup_ci_worktree!()
    add_github_merge!(worktree, subject: "Merge feature into main")

    assert {output, 1} = run(@range_guard, [], cd: worktree)
    assert output =~ "Merge feature into main"
  end

  test "the push_refs guard passes when there are no refs to push" do
    {worktree, _} = setup_ci_worktree!()
    assert {"", 0} = run_with_stdin(@push_refs_guard, "", cd: worktree)
  end

  test "the push_refs guard skips deletion pushes" do
    {worktree, _} = setup_ci_worktree!()
    {head_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    head_sha = String.trim(head_sha)
    stdin = "refs/heads/old-branch #{@zero_sha} refs/heads/old-branch #{head_sha}\n"
    assert {"", 0} = run_with_stdin(@push_refs_guard, stdin, cd: worktree)
  end

  test "the push_refs guard passes a valid conventional commit on an existing branch" do
    {worktree, _} = setup_ci_worktree!()
    {base_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    base_sha = String.trim(base_sha)

    File.write!(Path.join(worktree, "x"), "x")
    git!(worktree, ["add", "x"])
    git!(worktree, ["commit", "-m", "feat: add x"])

    {head_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    head_sha = String.trim(head_sha)

    stdin = "refs/heads/main #{head_sha} refs/heads/main #{base_sha}\n"
    assert {"", 0} = run_with_stdin(@push_refs_guard, stdin, cd: worktree)
  end

  test "the push_refs guard rejects a non-conventional commit on an existing branch" do
    {worktree, _} = setup_ci_worktree!()
    {base_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    base_sha = String.trim(base_sha)

    File.write!(Path.join(worktree, "y"), "y")
    git!(worktree, ["add", "y"])
    git!(worktree, ["commit", "-m", "this is not conventional"])

    {head_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    head_sha = String.trim(head_sha)

    stdin = "refs/heads/main #{head_sha} refs/heads/main #{base_sha}\n"
    assert {output, 1} = run_with_stdin(@push_refs_guard, stdin, cd: worktree)
    assert output =~ "this is not conventional"
  end

  test "the push_refs guard passes a valid conventional commit on a new branch" do
    {worktree, _} = setup_ci_worktree!()

    git!(worktree, ["checkout", "-b", "new-feature"])
    File.write!(Path.join(worktree, "f"), "f")
    git!(worktree, ["add", "f"])
    git!(worktree, ["commit", "-m", "feat: add f"])

    {head_sha, 0} = System.cmd("git", ["rev-parse", "HEAD"], cd: worktree)
    head_sha = String.trim(head_sha)

    stdin = "refs/heads/new-feature #{head_sha} refs/heads/new-feature #{@zero_sha}\n"
    assert {"", 0} = run_with_stdin(@push_refs_guard, stdin, cd: worktree)
  end

  test "git-hooks/ directory contains only the commit-msg and pre-push adapters" do
    hooks_dir = Path.expand("../git-hooks", __DIR__)
    entries = File.ls!(hooks_dir) |> Enum.sort()
    assert entries == ["commit-msg", "pre-push"]
  end

  # Creates a no-fast-forward merge commit on `main` from a throwaway `feature`
  # branch. Defaults simulate GitHub's "Update branch" identity and subject;
  # these remain subject to validation because commit metadata is forgeable.
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

  # Creates a git repo in a temp dir with origin set up and ci/ scripts copied
  # in so validate_commit_range.sh and validate_push_refs.sh can find
  # validate_conventional_subject.sh via $repo_top/ci/.
  # Uses a cryptographic nonce so collisions cannot occur across BEAM VM
  # restarts (unlike System.unique_integer/1 which resets each run).
  defp setup_ci_worktree! do
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

    ci_dir = Path.join(worktree, "ci")
    File.mkdir_p!(ci_dir)

    for guard <- [@subject_guard, @range_guard, @push_refs_guard] do
      destination = Path.join(ci_dir, Path.basename(guard))
      File.cp!(guard, destination)
      File.chmod!(destination, 0o755)
    end

    {worktree, ci_dir}
  end

  defp run_with_stdin(command, stdin_content, opts \\ []) do
    nonce = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    stdin_file = Path.join(System.tmp_dir!(), "linear_cli_stdin_#{nonce}")
    File.write!(stdin_file, stdin_content)
    on_exit(fn -> File.rm(stdin_file) end)
    opts = Keyword.put(opts, :stderr_to_stdout, true)
    System.cmd("sh", ["-c", "#{command} < #{stdin_file}"], opts)
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
