defmodule LinearCli.ApiTest do
  # async: false - the missing-key test below unsets the real (VM-global,
  # not per-process) LINEAR_API_KEY env var. test_helper.exs sets a default
  # for the rest of the suite; running this module concurrently with it would race.
  use ExUnit.Case, async: false

  test "returns {:ok, data} on a successful response" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"viewer" => %{"id" => "123"}}})
    end)

    assert LinearCli.Api.call("{ viewer { id } }") == {:ok, %{"viewer" => %{"id" => "123"}}}
  end

  test "returns {:error, {:graphql_errors, errors}} when the response has errors but no data" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"errors" => [%{"message" => "boom"}]})
    end)

    assert LinearCli.Api.call("{ viewer { id } }") ==
             {:error, {:graphql_errors, [%{"message" => "boom"}]}}
  end

  test "returns {:ok, data} when the response has both data and errors (partial success)" do
    # Linear returns HTTP 200 with both "data": {"issue": null} and "errors"
    # when the requested entity doesn't exist. Returning {:ok, data} lets callers
    # handle the nil field themselves (e.g. fetch_one/1's {:not_found, id} clause)
    # rather than discarding the data and surfacing an opaque graphql_errors tuple.
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{
        "data" => %{"issue" => nil},
        "errors" => [%{"message" => "Entity not found: Issue", "path" => ["issue"]}]
      })
    end)

    assert LinearCli.Api.call("{ issue(id: $id) { id } }") == {:ok, %{"issue" => nil}}
  end

  test "returns {:error, {:unexpected_response, body}} when there's neither data nor errors" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"wat" => true})
    end)

    assert LinearCli.Api.call("{ viewer { id } }") ==
             {:error, {:unexpected_response, %{"wat" => true}}}
  end

  test "returns {:error, {:http_error, status, body}} on a non-200 response" do
    # 404, not 500 - 500 is in Req's default transient-retry list and would make
    # this test slow (and call the stub multiple times) for no reason.
    Req.Test.stub(LinearCli.Api, fn conn ->
      conn |> Plug.Conn.put_status(404) |> Req.Test.json(%{"message" => "not found"})
    end)

    assert LinearCli.Api.call("{ viewer { id } }") ==
             {:error, {:http_error, 404, %{"message" => "not found"}}}
  end

  test "returns {:error, :missing_api_key} when LINEAR_API_KEY is unset" do
    previous = System.get_env("LINEAR_API_KEY")
    System.delete_env("LINEAR_API_KEY")
    on_exit(fn -> previous && System.put_env("LINEAR_API_KEY", previous) end)

    assert LinearCli.Api.call("{ viewer { id } }") == {:error, :missing_api_key}
  end

  test "passes the document and variables as the GraphQL request body" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      assert Jason.decode!(body) == %{"query" => "{ viewer { id } }", "variables" => %{"x" => 1}}
      Req.Test.json(conn, %{"data" => %{}})
    end)

    assert LinearCli.Api.call("{ viewer { id } }", %{"x" => 1}) == {:ok, %{}}
  end
end
