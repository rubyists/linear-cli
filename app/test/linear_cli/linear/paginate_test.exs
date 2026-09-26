defmodule LinearCli.Linear.PaginateTest do
  use ExUnit.Case, async: true

  alias LinearCli.Linear.Paginate

  defp response(ids, has_next_page, end_cursor) do
    %{
      "data" => %{
        "issues" => %{
          "edges" => Enum.map(ids, &%{"node" => %{"id" => &1}, "cursor" => "row-#{&1}"}),
          "pageInfo" => %{"hasNextPage" => has_next_page, "endCursor" => end_cursor}
        }
      }
    }
  end

  defp variables_fun(after_cursor), do: %{"after" => after_cursor}

  test "uses the default 100-record limit" do
    test_pid = self()

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      cursor = Jason.decode!(body)["variables"]["after"]
      send(test_pid, {:cursor, cursor})

      response =
        case cursor do
          nil -> response(1..50, true, "c1")
          "c1" -> response(51..120, true, "c2")
        end

      Req.Test.json(conn, response)
    end)

    assert {:ok, values} = Paginate.all("query", "issues", &variables_fun/1, & &1["id"])
    assert length(values) == 100
    assert List.first(values) == 1
    assert List.last(values) == 100
    assert_receive {:cursor, nil}
    assert_receive {:cursor, "c1"}
    refute_receive {:cursor, "c2"}
  end

  test "returns the first page and reports more records without following the cursor" do
    test_pid = self()

    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      cursor = Jason.decode!(body)["variables"]["after"]
      send(test_pid, {:cursor, cursor})
      Req.Test.json(conn, response([1, 2], true, "c1"))
    end)

    assert {:ok, [1, 2], true} =
             Paginate.first_page("query", "issues", &variables_fun/1, & &1["id"])

    assert_receive {:cursor, nil}
    refute_receive {:cursor, "c1"}
  end

  test "returns an error when the API repeats a continuation cursor" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      cursor = Jason.decode!(body)["variables"]["after"]

      response =
        case cursor do
          nil -> response([1], true, "c1")
          "c1" -> response([2], true, "c1")
        end

      Req.Test.json(conn, response)
    end)

    assert {:error, {:non_advancing_cursor, "c1"}} =
             Paginate.all("query", "issues", &variables_fun/1, & &1["id"])
  end
end
