defmodule LinearCli.Linear.Comment do
  @moduledoc """
  A Linear issue comment. Ported from vendor/ruby-linear-cli/lib/linear/models/comment.rb.

  Never queried top-level in the Ruby original - only ever nested inside an
  issue's fragment (or created via the `commentCreate` mutation, ported in a
  later phase alongside the other write commands). No actions defined here yet.
  """

  use Ash.Resource, domain: LinearCli.Linear

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
