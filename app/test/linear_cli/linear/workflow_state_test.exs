defmodule LinearCli.Linear.WorkflowStateTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear

  test "workflow_states_by_team/1 fetches a team's workflow states" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      %{"variables" => %{"teamId" => "t1"}} = Jason.decode!(body)

      Req.Test.json(conn, %{
        "data" => %{
          "team" => %{
            "states" => %{
              "nodes" => [
                %{
                  "id" => "s1",
                  "name" => "Done",
                  "position" => 3.0,
                  "type" => "completed",
                  "description" => nil
                }
              ]
            }
          }
        }
      })
    end)

    assert {:ok, [%Linear.WorkflowState{name: "Done", type: "completed"}]} =
             Linear.workflow_states_by_team("t1")
  end
end
