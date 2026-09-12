defmodule LinearCli.CLI.Issue.CreationTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureIO

  alias LinearCli.CLI.Issue.Creation
  alias LinearCli.Linear.Issue

  defp stub_responses(pairs) do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"query" => query} = Jason.decode!(body)

      case Enum.find(pairs, fn {match, _resp} -> String.contains?(query, match) end) do
        {_match, response} -> Req.Test.json(conn, response)
        nil -> raise "no stub matched query: #{query}"
      end
    end)
  end

  defp team_projects(projects) do
    %{"data" => %{"team" => %{"projects" => %{"nodes" => projects}}}}
  end

  describe "make_da_issue!/1 (Ruby: CLI::Issue#make_da_issue!)" do
    test "creates the issue with resolved title/description/team/labels/project" do
      stub_responses([
        {"team(id: $id)",
         %{
           "data" => %{
             "team" => %{
               "id" => "t1",
               "key" => "ENG",
               "name" => "Engineering",
               "description" => nil
             }
           }
         }},
        {"issueLabels",
         %{
           "data" => %{
             "issueLabels" => %{
               "edges" => [
                 %{
                   "node" => %{
                     "id" => "l1",
                     "name" => "urgent",
                     "description" => nil,
                     "isGroup" => false
                   }
                 }
               ]
             }
           }
         }},
        {"projects(first: 100",
         team_projects([
           %{
             "id" => "p1",
             "name" => "Manhattan Rollout",
             "content" => nil,
             "slugId" => "abc",
             "description" => nil,
             "url" => "https://linear.app/x/project/manhattan-rollout-abc"
           }
         ])},
        {"issueCreate",
         %{
           "data" => %{
             "issueCreate" => %{
               "issue" => %{
                 "id" => "i2",
                 "identifier" => "CRY-2",
                 "title" => "New thing",
                 "branchName" => "cry-2-new-thing",
                 "description" => "Some description",
                 "assignee" => nil,
                 "team" => %{"id" => "t1", "key" => "ENG", "name" => "Engineering"}
               }
             }
           }
         }}
      ])

      assert capture_io(fn ->
               assert {:ok, %Issue{identifier: "CRY-2"}} =
                        Creation.make_da_issue!(
                          title: "New thing",
                          description: "Some description",
                          team: "ENG",
                          labels: ["urgent"],
                          project: "Manhattan Rollout"
                        )
             end) == ""
    end
  end
end
