defmodule LinearCli.Api do
  @moduledoc """
  Thin GraphQL client for the Linear API.

  Ported from `Rubyists::Linear::GraphApi` (vendor/ruby-linear-cli/lib/linear/api.rb),
  with one deliberate behavior change: callers pass GraphQL `variables` instead of
  interpolating values into the query string, closing the injection risk present in
  the Ruby `Issue#add_comment` path.
  """

  @base_url "https://api.linear.app/graphql"

  @doc """
  Runs a GraphQL query or mutation against the Linear API.

  Returns `{:ok, data}` with the decoded `"data"` object, or `{:error, reason}`
  where `reason` is one of:

    * `:missing_api_key` - `LINEAR_API_KEY` is not set
    * `{:graphql_errors, errors}` - the response body has errors but no `"data"` field
    * `{:unexpected_response, body}` - a 200 response with neither `"data"` nor `"errors"`
    * `{:http_error, status, body}` - a non-200 response
    * `{:transport_error, exception}` - the request itself failed (timeout, DNS, etc.)

  GraphQL partial-success responses (both `"data"` and `"errors"` present) return
  `{:ok, data}` — the `"errors"` are field-level annotations on an otherwise valid
  result. Callers inspect nil fields (e.g. `{:ok, %{"issue" => nil}}`) to detect
  entity-not-found, which is how Linear signals a missing entity when the query ran.
  """
  def call(document, variables \\ %{}) do
    with {:ok, api_key} <- fetch_api_key() do
      [
        method: :post,
        url: @base_url,
        json: %{query: document, variables: variables},
        headers: [{"authorization", api_key}],
        retry: :transient,
        max_retries: 5
      ]
      |> Keyword.merge(Application.get_env(:linear_cli, :req_options, []))
      |> Req.request()
      |> handle_response()
    end
  end

  # "data" takes precedence: a response with both "data" and "errors" is a
  # GraphQL partial-success - the query ran and produced a result (possibly
  # with nil fields); callers handle nil fields themselves. Only fall back to
  # {:error, {:graphql_errors, ...}} when there is no "data" at all.
  # Guard: only match when data is a map (the expected shape). A null top-level
  # "data" means the entire operation failed; in that case the errors clause
  # below provides the more informative result.
  defp handle_response({:ok, %Req.Response{status: 200, body: %{"data" => data}}})
       when is_map(data) do
    {:ok, data}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: %{"errors" => [_ | _] = errors}}}) do
    {:error, {:graphql_errors, errors}}
  end

  defp handle_response({:ok, %Req.Response{status: 200, body: body}}) do
    {:error, {:unexpected_response, body}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, exception}) do
    {:error, {:transport_error, exception}}
  end

  defp fetch_api_key do
    case System.fetch_env("LINEAR_API_KEY") do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :missing_api_key}
    end
  end
end
