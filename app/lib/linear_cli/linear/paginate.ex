defmodule LinearCli.Linear.Paginate do
  @moduledoc """
  Cursor-based pagination over a GraphQL connection (`edges { node { ... } cursor }`
  plus `pageInfo { hasNextPage endCursor }`).

  Ported from `Rubyists::Linear::BaseModel::ClassMethods#all`
  (vendor/ruby-linear-cli/lib/linear/models/base_model/class_methods.rb).
  """

  alias LinearCli.Api

  @doc """
  Fetches pages via `LinearCli.Api.call(document, variables(after_cursor))` until
  `max` records are collected or the API reports no more pages, decoding each raw
  node through `decode_fun`.

  `field_name` is the top-level response key (e.g. `"teams"`) holding
  `edges`/`pageInfo`. `variables_fun` receives the current `after` cursor
  (`nil` on the first page) and returns the GraphQL variables map.
  """
  def all(document, field_name, variables_fun, decode_fun, max \\ 100) do
    do_all(document, field_name, variables_fun, decode_fun, nil, max, [])
  end

  defp do_all(document, field_name, variables_fun, decode_fun, after_cursor, max, acc) do
    with {:ok, data} <- Api.call(document, variables_fun.(after_cursor)),
         {:ok, %{"edges" => edges, "pageInfo" => page_info}} <-
           fetch_connection(data, field_name) do
      acc = acc ++ Enum.map(edges, &decode_fun.(&1["node"]))

      if length(acc) >= max or !page_info["hasNextPage"] do
        {:ok, Enum.take(acc, max)}
      else
        do_all(document, field_name, variables_fun, decode_fun, page_info["endCursor"], max, acc)
      end
    else
      {:error, {:http_error, status, _body}} -> {:error, {:http_error, status}}
      {:error, reason} -> {:error, reason}
    end
  end

  # Safely extracts the named connection from the response data. Returns
  # {:error, {:unexpected_response, ...}} instead of crashing with KeyError
  # when the field is absent or not the expected connection shape.
  defp fetch_connection(data, field_name) do
    case data do
      %{^field_name => %{"edges" => _, "pageInfo" => _} = connection} ->
        {:ok, connection}

      %{^field_name => other} ->
        {:error, {:unexpected_response, other}}

      _ ->
        {:error, {:unexpected_response, data}}
    end
  end
end
