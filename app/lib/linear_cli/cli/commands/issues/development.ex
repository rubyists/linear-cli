defmodule LinearCli.CLI.Commands.Issues.Development do
  @moduledoc """
  Issue development commands: develop, PR, and take.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/develop.rb,
  pr.rb, and take.rb.
  """

  alias LinearCli.CLI.{Display, Prompt}
  alias LinearCli.CLI.Issue.{Assignment, PullRequest}
  alias LinearCli.Git

  @doc """
  Ported from commands/issue/develop.rb: resolves/self-assigns `issue_id`
  (`LinearCli.CLI.Issue.Assignment.gimme_da_issue!/2`), checks out its
  `branch_name` (creating it first if it doesn't exist locally yet), then
  pulls it (or, if there's no upstream tracking branch yet, pushes it to
  `origin` and sets one up).

  `opts` (this port's addition, not part of Ruby's `call(issue_id:,
  **options)`) forwards to `LinearCli.Git.checkout_branch/2`/
  `pull_or_push_new_branch!/2` (`:cwd`) and
  `LinearCli.CLI.Issue.Assignment.gimme_da_issue!/2` (`:me`) - pass overrides
  in tests so this never shells out to real git or hits a real `viewer` query;
  real callers omit it.
  """
  @spec issue_develop(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_develop(result, opts \\ [])
  def issue_develop(%{args: %{issue_id: issue_id}}, opts), do: run_develop(issue_id, opts)

  @doc """
  Ported from commands/issue/pr.rb: resolves/self-assigns `issue_id`, checks
  out its branch (creating it first if needed - no pull/push here, unlike
  `issue_develop/2`), then opens a PR via
  `LinearCli.CLI.Issue.PullRequest.issue_pr/2`.

  `opts` (this port's addition): `:cwd` (forwarded to
  `LinearCli.Git.checkout_branch/2`), `:me` (forwarded to
  `gimme_da_issue!/2`), `:runner` (forwarded to `issue_pr/2`, so this never
  shells out to a real `gh` in tests). Real callers omit it.
  """
  @spec issue_pr(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_pr(result, opts \\ [])

  def issue_pr(%{args: %{issue_id: issue_id}, options: options}, opts) do
    with {:ok, issue} <- Assignment.gimme_da_issue!(issue_id, opts),
         {:ok, _branch} <- Git.checkout_branch(issue.branch_name, opts) do
      Prompt.ok("Checked out branch #{issue.branch_name}")

      pr_opts =
        [title: options.title, description: options.description]
        |> maybe_put(:runner, opts[:runner])

      PullRequest.issue_pr(issue, pr_opts)
    end
  end

  @doc """
  Ported from commands/issue/take.rb: self-assigns every issue id in
  `unknown` (Ruby's `issue_ids:`, a variadic positional argument - Optimus
  has no declared-arity equivalent to `type: :array` positional args, so,
  like `issue_list/1`'s own `ids`, it's captured via the subcommand's
  `allow_unknown_args: true` + the parse result's `unknown` list), skipping
  (and warning about) any id that doesn't exist rather than aborting the
  whole batch - matching Ruby's `rescue NotFoundError => e ... next` inside
  its `filter_map`.

  `opts` (this port's addition) forwards to
  `LinearCli.CLI.Issue.Assignment.gimme_da_issue!/2` (`:me`); real callers
  omit it.
  """
  @spec issue_take(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_take(result, opts \\ [])

  def issue_take(%{unknown: issue_ids, options: options}, opts) do
    opts = maybe_put_status(opts, Map.get(options, :status))

    with {:ok, updates} <- take_issues(issue_ids, opts) do
      Display.show(updates, %{output: options.output})
      :ok
    end
  end

  defp run_develop(issue_id, opts) do
    with {:ok, issue} <- Assignment.gimme_da_issue!(issue_id, opts),
         {:ok, _branch} <- Git.checkout_branch(issue.branch_name, opts) do
      Prompt.ok("Checked out branch #{issue.branch_name}")
      finish_pull_or_push(issue.branch_name, opts)
    end
  end

  # Ported from `SubCommands#pull_or_push_new_branch!`'s own prompt calls
  # (`prompt.warn`/`prompt.ok`, printed around the push+set-upstream fallback
  # only) plus `Issue::Develop#call`'s trailing `prompt.ok 'Ready to
  # develop!'` (printed unconditionally, after either branch).
  defp finish_pull_or_push(branch_name, opts) do
    case Git.pull_or_push_new_branch!(branch_name, opts) do
      {:ok, {:pulled, _output}} ->
        Prompt.ok("Ready to develop!")
        :ok

      {:ok, {:pushed_new_branch, _branch_name}} ->
        Prompt.warn("Upstream branch not found, pushing local #{branch_name} to origin")
        Prompt.ok("Set upstream to origin/#{branch_name}")
        Prompt.ok("Ready to develop!")
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  defp maybe_put_status(opts, nil), do: opts
  defp maybe_put_status(opts, status), do: Keyword.put(opts, :status, status)

  defp take_issues(issue_ids, opts) do
    issue_ids
    |> Enum.reduce_while({:ok, []}, fn issue_id, {:ok, acc} ->
      case Assignment.gimme_da_issue!(issue_id, opts) do
        {:ok, issue} ->
          {:cont, {:ok, [issue | acc]}}

        {:error, %Ash.Error.Unknown{errors: [%{value: [{:not_found, id}]} | _]}} ->
          Prompt.warn("No issue found with id #{id}")
          {:cont, {:ok, acc}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      error -> error
    end
  end
end
