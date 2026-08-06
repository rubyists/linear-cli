defmodule LinearCli.Linear.Comment do
  @moduledoc """
  A Linear issue comment. Ported from vendor/ruby-linear-cli/lib/linear/models/comment.rb.

  Never queried top-level in the Ruby original - only ever nested inside an
  issue's fragment, except for the `create` action below (Ruby:
  `Issue#add_comment`), which creates a comment via the `commentCreate`
  mutation.
  """

  use Ash.Resource, domain: LinearCli.Linear

  actions do
    # Ruby: Issue#add_comment(comment)
    create :create do
      argument :issue_identifier, :string, allow_nil?: false
      argument :body, :string, allow_nil?: false
      manual LinearCli.Linear.Comment.Create
    end
  end

  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :body, :string, public?: true
    attribute :url, :string, public?: true
    attribute :user, :term, public?: true
  end

  @doc "GraphQL field selection for a comment's own fields (Ruby: Comment::Base)."
  def base_fields do
    "id body url user { #{LinearCli.Linear.User.fields_with_teams()} } createdAt updatedAt"
  end

  @doc false
  def from_map(map) do
    struct!(__MODULE__,
      id: map["id"],
      body: map["body"],
      url: map["url"],
      user: map["user"] && LinearCli.Linear.User.from_map(map["user"])
    )
  end
end

defmodule LinearCli.Linear.Comment.Create do
  @moduledoc false
  use Ash.Resource.ManualCreate

  alias LinearCli.Api
  alias LinearCli.Linear.Comment

  # Ruby: Issue#add_comment(comment) - commentCreate mutation, returns the
  # created comment via Comment::Base's own field shape.
  def create(changeset, _opts, _context) do
    args = changeset.arguments

    case Api.call(document(), %{"issueId" => args.issue_identifier, "body" => args.body}) do
      {:ok, %{"commentCreate" => %{"comment" => comment_map}}} when is_map(comment_map) ->
        {:ok, Comment.from_map(comment_map)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # A function, not a module attribute: Comment.base_fields/0 reaches into
  # User (another file), so it must be evaluated at call time.
  defp document do
    "mutation($issueId: String!, $body: String!) { commentCreate(input: { issueId: $issueId, body: $body }) { comment { #{Comment.base_fields()} } } }"
  end
end
