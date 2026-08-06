defmodule LinearCli.ApiTest do
  use ExUnit.Case, async: true

  setup do
    System.put_env("LINEAR_API_KEY", "test-key")
    on_exit(fn -> System.delete_env("LINEAR_API_KEY") end)
  end

  test "returns {:ok, data} on a successful response" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"viewer" => %{"id" => "123"}}})
    end)

    assert LinearCli.Api.call("{ viewer { id } }") == {:ok, %{"viewer" => %{"id" => "123"}}}
  end

  test "returns {:error, {:graphql_errors, errors}} when the response has errors" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"errors" => [%{"message" => "boom"}]})
    end)

    assert LinearCli.Api.call("{ viewer { id } }") ==
             {:error, {:graphql_errors, [%{"message" => "boom"}]}}
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
    System.delete_env("LINEAR_API_KEY")
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
