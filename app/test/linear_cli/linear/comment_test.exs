defmodule LinearCli.Linear.CommentTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  describe "add_comment/2+" do
    test "sends issueId/body and returns the created comment via base_fields" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)

        %{"variables" => %{"issueId" => issue_id, "body" => comment_body}} = Jason.decode!(body)

        assert issue_id == "CRY-1"
        assert comment_body == "Looks good"

        Req.Test.json(conn, %{
          "data" => %{
            "commentCreate" => %{
              "comment" => %{
                "id" => "c1",
                "body" => "Looks good",
                "url" => "https://linear.app/team/issue/CRY-1#comment-c1",
                "user" => %{
                  "id" => "u1",
                  "name" => "Ada",
                  "email" => "ada@example.com",
                  "teams" => %{"nodes" => []}
                }
              }
            }
          }
        })
      end)

      assert {:ok, comment} = Linear.add_comment("CRY-1", "Looks good")
      assert comment.body == "Looks good"
      assert comment.user.name == "Ada"
    end

    test "surfaces a GraphQL error" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        Req.Test.json(conn, %{"errors" => [%{"message" => "no such issue"}]})
      end)

      assert {:error, %Ash.Error.Unknown{}} = Linear.add_comment("nope", "Looks good")
    end
  end
end
