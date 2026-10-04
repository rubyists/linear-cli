defmodule LinearCli.CLI.Commands.Issues.Development do
  @moduledoc """
  Issue development commands: develop, PR, and take.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/develop.rb,
  pr.rb, and take.rb.
  """

  alias LinearCli.CLI.{Display, Output}
  alias LinearCli.CLI.Issue.{Assignment, Identifiers, PullRequest}
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

  def issue_develop(%{args: %{issue_id: issue_id}} = result, opts) do
    opts = maybe_put(opts, :output, result_output(result))

    with :ok <- run_develop(issue_id, opts) do
      Output.success("issue_develop", %{"issue" => issue_id}, opts)
      :ok
    end
  end

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
    opts = maybe_put(opts, :output, Map.get(options, :output, "text"))

    with :ok <- validate_json_pr(options),
         {:ok, issue} <- Assignment.gimme_da_issue!(issue_id, opts),
         {:ok, _branch} <- Git.checkout_branch(issue.branch_name, opts) do
      Output.status(:ok, "Checked out branch #{issue.branch_name}", opts)

      pr_opts =
        [title: options.title, description: options.description, output: opts[:output]]
        |> maybe_put(:runner, opts[:runner])

      with :ok <- PullRequest.issue_pr(issue, pr_opts) do
        Output.success("issue_pr", %{"issue" => issue.identifier}, opts)
        :ok
      end
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
    opts =
      opts
      |> maybe_put_status(Map.get(options, :status))
      |> maybe_put(:output, Map.get(options, :output, "text"))

    with {:ok, updates} <- take_issues(issue_ids, opts) do
      output = Map.get(options, :output, "text")
      value = if output == "json", do: one_or_many(updates), else: updates
      Display.show(value, %{output: output})
      :ok
    end
  end

  defp run_develop(issue_id, opts) do
    with {:ok, issue} <- Assignment.gimme_da_issue!(issue_id, opts),
         {:ok, _branch} <- Git.checkout_branch(issue.branch_name, opts) do
      Output.status(:ok, "Checked out branch #{issue.branch_name}", opts)
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
        Output.status(:ok, "Ready to develop!", opts)
        :ok

      {:ok, {:pushed_new_branch, _branch_name}} ->
        Output.status(
          :warn,
          "Upstream branch not found, pushing local #{branch_name} to origin",
          opts
        )

        Output.status(:ok, "Set upstream to origin/#{branch_name}", opts)
        Output.status(:ok, "Ready to develop!", opts)
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put(list, _key, nil), do: list
  defp maybe_put(list, key, value), do: Keyword.put(list, key, value)

  defp result_output(%{options: options}), do: Map.get(options, :output, "text")
  defp result_output(_result), do: "text"

  defp validate_json_pr(options) do
    if Map.get(options, :output, "text") != "json" do
      :ok
    else
      cond do
        is_nil(Map.get(options, :title)) ->
          {:error, {:smells_bad, "JSON output requires --title for issue pr"}}

        is_nil(Map.get(options, :description)) ->
          {:error, {:smells_bad, "JSON output requires --description for issue pr"}}

        true ->
          :ok
      end
    end
  end

  defp maybe_put_status(opts, nil), do: opts
  defp maybe_put_status(opts, status), do: Keyword.put(opts, :status, status)

  defp take_issues(issue_ids, opts) do
    with {:ok, resolved_ids} <- preflight_take_ids(issue_ids, opts) do
      resolved_ids
      |> Enum.reduce_while({:ok, []}, fn issue_id, {:ok, acc} ->
        case Assignment.gimme_da_issue!(issue_id, opts) do
          {:ok, issue} ->
            {:cont, {:ok, [issue | acc]}}

          {:error, %Ash.Error.Unknown{errors: [%{value: [{:not_found, id}]} | _]}} ->
            Output.status(:warn, "No issue found with id #{id}", opts)
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

  defp preflight_take_ids(issue_ids, opts) do
    if Keyword.get(opts, :output, "text") == "json" do
      Identifiers.expand_issue_ids(issue_ids, output: "json")
    else
      {:ok, issue_ids}
    end
  end

  defp one_or_many([one]), do: one
  defp one_or_many(many), do: many
end
