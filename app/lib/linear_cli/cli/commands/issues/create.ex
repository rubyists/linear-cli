defmodule LinearCli.CLI.Commands.Issues.Create do
  @moduledoc """
  Issue create command.
  Ported from vendor/ruby-linear-cli/lib/linear/commands/issue/create.rb.
  """

  alias LinearCli.CLI.{Display, Prompt}
  alias LinearCli.CLI.Issue.{Assignment, Creation}
  alias LinearCli.Git

  @doc """
  Ported from commands/issue/create.rb: resolves every field
  (`LinearCli.CLI.Issue.Creation.make_da_issue!/1`), optionally self-assigns it
  (`prompt.yes?('Do you want to take this issue?')`, unless `--no-take` was
  given), displays it, then, if `--dev` was given, chains straight into the
  same flow as `issue_develop/2`
  (Ruby: `Rubyists::Linear::CLI::Issue::Develop.new.call(issue_id: issue.id,
  **options)`).

  `opts` isn't part of Ruby's `call(**options)` arity - it exists purely to
  inject test doubles into whatever this command chains into: `:me`
  (`Assignment.gimme_da_issue!/2`, both for the self-assign prompt and, if
  `--dev` fires, `run_develop/2`'s own re-fetch), `:cwd`
  (`LinearCli.Git.checkout_branch/2`/`pull_or_push_new_branch!/2`, only
  reached with `--dev`). Real callers (`LinearCli.CLI.main/2`) omit it.
  """
  @spec issue_create(Optimus.ParseResult.t(), keyword()) :: :ok | {:error, term()}
  def issue_create(result, opts \\ [])

  def issue_create(%{options: options, flags: flags}, opts) do
    with :ok <- validate_no_take_develop(flags),
         :ok <- validate_body_file_exclusion(options, :description, "--description"),
         {:ok, description} <- resolve_body_from_file(options, :description),
         create_opts = [
           title: options.title,
           description: description,
           team: options.team,
           labels: options.labels,
           project: options.project,
           yes: flags.yes
         ],
         {:ok, issue} <- Creation.make_da_issue!(create_opts),
         :ok <- maybe_take(issue, flags, opts) do
      Display.show(issue, %{output: options.output})
      if flags.develop, do: run_develop(issue.id, opts), else: :ok
    end
  end

  defp validate_no_take_develop(%{no_take: true, develop: true}),
    do: {:error, {:smells_bad, "--no-take cannot be used with --dev"}}

  defp validate_no_take_develop(_flags), do: :ok

  defp maybe_take(_issue, %{no_take: true}, _opts), do: :ok

  defp maybe_take(issue, %{yes: true}, opts) do
    case Assignment.gimme_da_issue!(issue.id, opts) do
      {:ok, _updated} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_take(issue, _flags, opts) do
    if Prompt.yes?("Do you want to take this issue?") do
      case Assignment.gimme_da_issue!(issue.id, opts) do
        {:ok, _updated} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
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

  defp validate_body_file_exclusion(options, text_key, flag_name) do
    if not is_nil(Map.get(options, :body_file)) and not is_nil(Map.get(options, text_key)) do
      {:error, {:smells_bad, "give #{flag_name} or --body-file, not both"}}
    else
      :ok
    end
  end

  defp resolve_body_from_file(options, text_key) do
    case Map.get(options, :body_file) do
      nil -> {:ok, Map.get(options, text_key)}
      "-" -> {:ok, read_stdin()}
      path -> File.read(path)
    end
  end

  defp read_stdin do
    case IO.read(:stdio, :eof) do
      :eof -> ""
      data -> data
    end
  end
end
