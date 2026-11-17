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

    test "extracts createdAt and updatedAt from the API response" do
      Req.Test.stub(LinearCli.Api, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        %{"variables" => %{"issueId" => _, "body" => _}} = Jason.decode!(body)

        Req.Test.json(conn, %{
          "data" => %{
            "commentCreate" => %{
              "comment" => %{
                "id" => "c1",
                "body" => "Hello",
                "url" => "https://linear.app/team/issue/CRY-1#comment-c1",
                "user" => nil,
                "createdAt" => "2024-03-10T14:00:00.000Z",
                "updatedAt" => "2024-03-10T14:05:00.000Z"
              }
            }
          }
        })
      end)

      assert {:ok, comment} = Linear.add_comment("CRY-1", "Hello")
      assert comment.created_at == "2024-03-10T14:00:00.000Z"
      assert comment.updated_at == "2024-03-10T14:05:00.000Z"
    end

    test "tolerates missing timestamp fields (nil stays nil)" do
      comment =
        LinearCli.Linear.Comment.from_map(%{
          "id" => "c2",
          "body" => "Old comment",
          "url" => nil,
          "user" => nil
        })

      assert is_nil(comment.created_at)
      assert is_nil(comment.updated_at)
    end
  end
end
