defmodule LinearCli.Git do
  @moduledoc """
  Git-related helpers.

  Ported from `Rubyists::Linear::CLI::SubCommands`
  (vendor/ruby-linear-cli/lib/linear/cli/sub_commands.rb), which shells out via the
  `git` Ruby gem and raises/exits on failure. This module instead shells out
  directly to the `git` binary via `System.cmd/3` and never raises - every
  function returns `{:ok, result}` or `{:error, reason}`, matching this
  codebase's established convention (see `LinearCli.Api`).

  Every function accepts an optional `cwd:` option (default `File.cwd!()`) so
  callers (and tests) can point them at a directory other than the real
  process working directory.
  """

  @typedoc "Options accepted by every function in this module."
  @type opts :: [cwd: String.t()]

  @doc """
  The name of the currently checked-out branch.

  Ported from `SubCommands#current_branch` (`git.current_branch`).
  """
  @spec current_branch(opts) :: {:ok, String.t()} | {:error, term()}
  def current_branch(opts \\ []) do
    git(["rev-parse", "--abbrev-ref", "HEAD"], opts)
  end

  @doc """
  Checks out `branch_name`, creating it first (from the current `HEAD`) if it
  does not already exist as a local branch.

  Ported from `SubCommands#branch_for` + `.checkout`
  (`git.branches.local.detect { ... } || git.branch(branch_name)`, then
  checked out).
  """
  @spec checkout_branch(String.t(), opts) :: {:ok, String.t()} | {:error, term()}
  def checkout_branch(branch_name, opts \\ []) do
    with {:ok, exists?} <- local_branch_exists?(branch_name, opts) do
      args = if exists?, do: ["checkout", branch_name], else: ["checkout", "-b", branch_name]

      case git(args, opts) do
        {:ok, _output} -> {:ok, branch_name}
        error -> error
      end
    end
  end

  @doc """
  Tries a `git pull`. If that fails because the current branch has no
  upstream tracking branch yet, pushes `branch_name` to `origin` and sets its
  upstream tracking to `origin/branch_name` instead.

  Ported from `SubCommands#pull_or_push_new_branch!`, which does the
  equivalent but raises straight through `Git::FailedError`/exits instead of
  returning a tagged tuple.
  """
  @spec pull_or_push_new_branch!(String.t(), opts) :: {:ok, term()} | {:error, term()}
  def pull_or_push_new_branch!(branch_name, opts \\ []) do
    case git(["pull"], opts) do
      {:ok, output} ->
        {:ok, {:pulled, output}}

      {:error, _reason} ->
        with {:ok, _push_output} <- git(["push", "origin", branch_name], opts),
             {:ok, _upstream_output} <-
               git(["branch", "--set-upstream-to=origin/#{branch_name}", branch_name], opts) do
          {:ok, {:pushed_new_branch, branch_name}}
        end
    end
  end

  @doc """
  The remote's default branch name (e.g. `"main"`), determined by resolving
  what `HEAD` points to on the `origin` remote - no clone or fetch required.

  Ported from `SubCommands#default_branch`
  (`Git.default_branch(git.remote.url)` from the `git` Ruby gem); the exact
  gem-internal implementation isn't replicated, only the observable behavior.
  """
  @spec default_branch(opts) :: {:ok, String.t()} | {:error, term()}
  def default_branch(opts \\ []) do
    with {:ok, url} <- git(["remote", "get-url", "origin"], opts),
         {:ok, symref_output} <- git(["ls-remote", "--symref", url, "HEAD"], opts) do
      parse_default_branch(symref_output)
    end
  end

  defp parse_default_branch(symref_output) do
    symref_output
    |> String.split("\n")
    |> Enum.find_value(fn line ->
      case Regex.run(~r{^ref:\s+refs/heads/(\S+)\s+HEAD$}, line) do
        [_, branch] -> branch
        nil -> nil
      end
    end)
    |> case do
      nil -> {:error, {:default_branch_not_found, symref_output}}
      branch -> {:ok, branch}
    end
  end

  defp local_branch_exists?(branch_name, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    case System.cmd("git", ["show-ref", "--verify", "--quiet", "refs/heads/#{branch_name}"],
           cd: cwd,
           stderr_to_stdout: true
         ) do
      {_output, 0} -> {:ok, true}
      {_output, _status} -> {:ok, false}
    end
  rescue
    e -> {:error, {:command_failed, e}}
  end

  defp git(args, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    case System.cmd("git", args, cd: cwd, stderr_to_stdout: true) do
      {output, 0} -> {:ok, String.trim(output)}
      {output, status} -> {:error, {:git_error, args, status, String.trim(output)}}
    end
  rescue
    e -> {:error, {:command_failed, e}}
  end
end
