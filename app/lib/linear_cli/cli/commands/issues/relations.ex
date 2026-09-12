defmodule LinearCli.CLI.Commands.Issues.Relations do
  @moduledoc """
  Issue relation commands: list, add, and remove.
  """

  alias LinearCli.CLI.{Display, Prompt}
  alias LinearCli.CLI.Issue.Identifiers
  alias LinearCli.Linear

  @doc """
  Lists the relationships for a single issue — both outbound (issues this one
  blocks/is-related-to/is-duplicate-of) and inbound (issues that block this
  one, etc.).

  Calls `Linear.issue_relations/1` which fetches both `relations` and
  `inverseRelations` from Linear and tags each with a direction.
  """
  @spec issue_relation_list(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_relation_list(%{args: %{issue_id: issue_id}, options: options}) do
    expanded_id = Identifiers.expand_issue_id(issue_id)

    with {:ok, relations} <- Linear.issue_relations(expanded_id) do
      Display.show(relations, %{output: options.output, relations: true})
      :ok
    end
  end

  @doc """
  Adds a relationship from `ISSUE` to one or more `RELATED_ISSUE`s.

  The first element of `unknown` is the subject issue; the remaining
  elements are the related issues.  `--type` controls direction:

  * `blocks`     — subject blocks each related issue (wire: `blocks`, subject → related)
  * `blocked-by` — subject is blocked by each related issue (wire: `blocks`, reversed: related → subject)
  * `related`    — subject is related to each related issue
  * `duplicate`  — subject is a duplicate of each related issue

  Each target is processed independently; partial failures do not roll back
  successful mutations.  All results are printed before returning; a non-zero
  exit identifies the overall failure count if any target failed.
  """
  @spec issue_relation_add(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_relation_add(%{unknown: []}),
    do: {:error, {:smells_bad, "ISSUE and at least one RELATED_ISSUE are required"}}

  def issue_relation_add(%{unknown: [_subject]}),
    do: {:error, {:smells_bad, "At least one RELATED_ISSUE is required"}}

  def issue_relation_add(%{unknown: [subject_id | related_ids], options: options}) do
    expanded_subject = Identifiers.expand_issue_id(subject_id)
    user_type = options.type

    results =
      Enum.map(related_ids, fn related_id ->
        expanded_related = Identifiers.expand_issue_id(related_id)
        add_single_relation(expanded_subject, expanded_related, user_type)
      end)

    print_relation_add_results(results, options.output)

    failed_count =
      Enum.count(results, fn r -> match?({:failed, _, _}, r) or match?({:self_link, _}, r) end)

    if failed_count > 0 do
      {:error, {:smells_bad, "#{failed_count} relation(s) failed to be created"}}
    else
      :ok
    end
  end

  defp add_single_relation(subject_id, related_id, _user_type) when subject_id == related_id do
    {:self_link, subject_id}
  end

  defp add_single_relation(subject_id, related_id, user_type) do
    {wire_issue_id, wire_related_id, wire_type, direction} =
      if user_type == "blocked-by" do
        {related_id, subject_id, "blocks", :inbound}
      else
        {subject_id, related_id, user_type, :outbound}
      end

    case Linear.create_issue_relation(wire_issue_id, wire_related_id, wire_type) do
      {:ok, relation} ->
        {:created, related_id, %{relation | direction: direction}}

      {:error, %Ash.Error.Unknown{errors: [%{value: [{:duplicate_relation, _}]} | _]}} ->
        {:exists, related_id}

      {:error, reason} ->
        {:failed, related_id, reason}
    end
  end

  defp print_relation_add_results(results, output) do
    if output == "json" do
      results
      |> Enum.map(&relation_add_result_to_plain/1)
      |> Jason.encode!(pretty: true)
      |> IO.puts()
    else
      Enum.each(results, &print_relation_add_result_text/1)
    end
  end

  defp relation_add_result_to_plain({:created, related_id, relation}) do
    %{
      "target" => related_id,
      "status" => "created",
      "relation" => Display.relation_to_plain(relation)
    }
  end

  defp relation_add_result_to_plain({:exists, related_id}) do
    %{"target" => related_id, "status" => "exists"}
  end

  defp relation_add_result_to_plain({:self_link, id}) do
    %{
      "target" => id,
      "status" => "error",
      "message" => "self-link: an issue cannot be related to itself"
    }
  end

  defp relation_add_result_to_plain({:failed, related_id, reason}) do
    msg = reason |> relation_add_error_message() |> truncate_message(200)
    %{"target" => related_id, "status" => "error", "message" => msg}
  end

  defp print_relation_add_result_text({:created, _related_id, relation}) do
    IO.puts(relation_add_created_text(relation))
  end

  defp print_relation_add_result_text({:exists, related_id}) do
    Prompt.ok("#{related_id}: relation already exists (no change)")
  end

  defp print_relation_add_result_text({:self_link, id}) do
    IO.puts(:stderr, "#{id}: self-link — an issue cannot be related to itself")
  end

  defp print_relation_add_result_text({:failed, related_id, reason}) do
    msg = relation_add_error_message(reason)
    IO.puts(:stderr, "#{related_id}: #{msg}")
  end

  defp relation_add_created_text(%{type: "blocks", issue: issue, related_issue: related}) do
    "#{issue.identifier} now blocks #{related.identifier}"
  end

  defp relation_add_created_text(%{type: "related", issue: issue, related_issue: related}) do
    "#{issue.identifier} is now related to #{related.identifier}"
  end

  defp relation_add_created_text(%{type: "duplicate", issue: issue, related_issue: related}) do
    "#{issue.identifier} is now a duplicate of #{related.identifier}"
  end

  defp relation_add_created_text(%{type: type, issue: issue, related_issue: related}) do
    "#{issue.identifier} is now a #{type} of #{related.identifier}"
  end

  defp relation_add_error_message(%Ash.Error.Unknown{
         errors: [%{value: [{:graphql_errors, [%{"message" => msg} | _]}]} | _]
       }),
       do: "Linear API error: #{msg}"

  defp relation_add_error_message(%Ash.Error.Unknown{
         errors: [%Ash.Error.Unknown.UnknownError{error: "unknown error: :missing_api_key"} | _]
       }),
       do: "LINEAR_API_KEY is not set"

  defp relation_add_error_message(_reason), do: "unexpected error"

  @doc """
  Removes a relationship from `ISSUE` to one or more `RELATED_ISSUE`s.

  The first element of `unknown` is the subject issue; the remaining elements
  are the related issues.  `--type` controls which stored relation to match:

  * `blocks`     — removes the relation where subject blocks each related issue
  * `blocked-by` — removes the relation where each related issue blocks subject
  * `related`    — removes the related relation
  * `duplicate`  — removes the duplicate relation

  Removing an absent relation is a per-target no-op (not an error).  If more
  than one stored relation matches for a target, that target fails and every
  matching relation ID is listed — nothing is deleted arbitrarily.

  Each target is processed independently; partial failures do not roll back
  successful deletions.  All results are printed before returning; a non-zero
  exit identifies the overall failure count if any target failed.
  """
  @spec issue_relation_remove(Optimus.ParseResult.t()) :: :ok | {:error, term()}
  def issue_relation_remove(%{unknown: []}),
    do: {:error, {:smells_bad, "ISSUE and at least one RELATED_ISSUE are required"}}

  def issue_relation_remove(%{unknown: [_subject]}),
    do: {:error, {:smells_bad, "At least one RELATED_ISSUE is required"}}

  def issue_relation_remove(%{unknown: [subject_id | related_ids], options: options}) do
    expanded_subject = Identifiers.expand_issue_id(subject_id)
    user_type = options.type

    with {:ok, all_relations} <- Linear.issue_relations(expanded_subject) do
      results =
        Enum.map(related_ids, fn related_id ->
          expanded_related = Identifiers.expand_issue_id(related_id)
          remove_single_relation(expanded_subject, expanded_related, user_type, all_relations)
        end)

      print_relation_remove_results(results, options.output)

      failed_count =
        Enum.count(results, fn r ->
          match?({:failed, _, _}, r) or match?({:ambiguous, _, _}, r) or
            match?({:self_link, _}, r)
        end)

      if failed_count > 0 do
        {:error, {:smells_bad, "#{failed_count} relation(s) failed to be removed"}}
      else
        :ok
      end
    end
  end

  defp remove_single_relation(subject_id, related_id, _user_type, _relations)
       when subject_id == related_id do
    {:self_link, subject_id}
  end

  defp remove_single_relation(subject_id, related_id, user_type, all_relations) do
    subject_id
    |> find_matching_relations(related_id, user_type, all_relations)
    |> do_remove(related_id)
  end

  defp do_remove([], related_id), do: {:absent, related_id}

  defp do_remove([relation], related_id) do
    case Linear.delete_issue_relation(relation) do
      :ok -> {:removed, related_id, relation}
      {:error, reason} -> {:failed, related_id, reason}
    end
  end

  defp do_remove(relations, related_id) do
    {:ambiguous, related_id, Enum.map(relations, & &1.id)}
  end

  # Finds stored relations that match the user-facing type and the given endpoint pair.
  # For `blocked-by`: the stored relation is `blocks` in the inbound direction, meaning
  # the related_id issue is the source (`issue`) and subject is the destination (`related_issue`).
  # For all other types: the stored relation is outbound with the subject as source.
  defp find_matching_relations(_subject_id, related_id, "blocked-by", all_relations) do
    Enum.filter(all_relations, fn rel ->
      rel.direction == :inbound and
        rel.type == "blocks" and
        rel.issue != nil and
        rel.issue.identifier == related_id
    end)
  end

  defp find_matching_relations(_subject_id, related_id, user_type, all_relations) do
    Enum.filter(all_relations, fn rel ->
      rel.direction == :outbound and
        rel.type == user_type and
        rel.related_issue != nil and
        rel.related_issue.identifier == related_id
    end)
  end

  defp print_relation_remove_results(results, output) do
    if output == "json" do
      results
      |> Enum.map(&relation_remove_result_to_plain/1)
      |> Jason.encode!(pretty: true)
      |> IO.puts()
    else
      Enum.each(results, &print_relation_remove_result_text/1)
    end
  end

  defp relation_remove_result_to_plain({:removed, related_id, relation}) do
    %{
      "target" => related_id,
      "status" => "removed",
      "relation" => Display.relation_to_plain(relation)
    }
  end

  defp relation_remove_result_to_plain({:absent, related_id}) do
    %{"target" => related_id, "status" => "absent"}
  end

  defp relation_remove_result_to_plain({:self_link, id}) do
    %{
      "target" => id,
      "status" => "error",
      "message" => "self-link: an issue cannot be related to itself"
    }
  end

  defp relation_remove_result_to_plain({:ambiguous, related_id, ids}) do
    %{
      "target" => related_id,
      "status" => "error",
      "message" => "ambiguous: multiple matching relations found: #{Enum.join(ids, ", ")}"
    }
  end

  defp relation_remove_result_to_plain({:failed, related_id, reason}) do
    msg = reason |> relation_remove_error_message() |> truncate_message(200)
    %{"target" => related_id, "status" => "error", "message" => msg}
  end

  defp print_relation_remove_result_text({:removed, _related_id, relation}) do
    IO.puts(relation_remove_removed_text(relation))
  end

  defp print_relation_remove_result_text({:absent, related_id}) do
    Prompt.ok("#{related_id}: relation not found (no change)")
  end

  defp print_relation_remove_result_text({:self_link, id}) do
    IO.puts(:stderr, "#{id}: self-link — an issue cannot be related to itself")
  end

  defp print_relation_remove_result_text({:ambiguous, related_id, ids}) do
    IO.puts(
      :stderr,
      "#{related_id}: ambiguous — #{length(ids)} matching relations: #{Enum.join(ids, ", ")}"
    )
  end

  defp print_relation_remove_result_text({:failed, related_id, reason}) do
    msg = relation_remove_error_message(reason)
    IO.puts(:stderr, "#{related_id}: #{msg}")
  end

  defp relation_remove_removed_text(%{type: "blocks", issue: issue, related_issue: related}) do
    "#{issue.identifier} no longer blocks #{related.identifier}"
  end

  defp relation_remove_removed_text(%{type: "related", issue: issue, related_issue: related}) do
    "#{issue.identifier} is no longer related to #{related.identifier}"
  end

  defp relation_remove_removed_text(%{type: "duplicate", issue: issue, related_issue: related}) do
    "#{issue.identifier} is no longer a duplicate of #{related.identifier}"
  end

  defp relation_remove_removed_text(%{type: type, issue: issue, related_issue: related}) do
    "#{issue.identifier} is no longer a #{type} of #{related.identifier}"
  end

  defp relation_remove_error_message(%Ash.Error.Unknown{
         errors: [%{value: [{:graphql_errors, [%{"message" => msg} | _]}]} | _]
       }),
       do: "Linear API error: #{msg}"

  defp relation_remove_error_message(%Ash.Error.Unknown{
         errors: [%Ash.Error.Unknown.UnknownError{error: "unknown error: :missing_api_key"} | _]
       }),
       do: "LINEAR_API_KEY is not set"

  defp relation_remove_error_message(_reason), do: "unexpected error"

  defp truncate_message(msg, max) when byte_size(msg) > max,
    do: String.slice(msg, 0, max) <> "…"

  defp truncate_message(msg, _max), do: msg
end
