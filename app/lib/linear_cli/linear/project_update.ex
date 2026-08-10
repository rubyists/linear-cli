defmodule LinearCli.Linear.ProjectUpdate do
  @moduledoc """
  A Linear project update - a status post on a project (e.g. "This week's
  progress..."), distinct from editing the project's own fields. New in
  this port - Ruby has no equivalent. Created via the projectUpdateCreate
  mutation (schema/LinearAPI.graphql).
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    create :create do
      argument :project_id, :string, allow_nil?: false
      argument :body, :string, allow_nil?: false
      argument :health, :string, allow_nil?: true
      manual LinearCli.Linear.ProjectUpdate.Create
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :body, :string, public?: true
    attribute :health, :string, public?: true
    attribute :url, :string, public?: true
  end

  @doc "GraphQL field selection for a project update's own fields."
  def base_fields do
    "id body health url createdAt"
  end

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      body: map["body"],
      health: map["health"],
      url: map["url"]
    )
  end
end

defmodule LinearCli.Linear.ProjectUpdate.Create do
  @moduledoc false
  use Ash.Resource.ManualCreate

  alias LinearCli.Api
  alias LinearCli.Linear.ProjectUpdate

  def create(changeset, _opts, _context) do
    args = changeset.arguments

    input =
      %{"projectId" => args.project_id, "body" => args.body}
      |> maybe_put_health(args.health)

    case Api.call(document(), %{"input" => input}) do
      {:ok, %{"projectUpdateCreate" => %{"projectUpdate" => update_map}}}
      when is_map(update_map) ->
        {:ok, ProjectUpdate.from_map(update_map)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_put_health(input, nil), do: input
  defp maybe_put_health(input, health), do: Map.put(input, "health", health)

  # A function, not a module attribute: ProjectUpdate.base_fields/0 reaches
  # into no other file today, but kept consistent with every other
  # document/0 in this codebase for the same reason they all are.
  defp document do
    "mutation($input: ProjectUpdateCreateInput!) { projectUpdateCreate(input: $input) { projectUpdate { #{ProjectUpdate.base_fields()} } } }"
  end
end
