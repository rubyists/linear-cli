defmodule LinearCli.CLI.Output do
  @moduledoc """
  Small command-level helpers for keeping JSON output on stdout valid.

  Commands still use `LinearCli.CLI.Display` for their values. This module only
  decides whether a value is JSON output and sends human-readable status lines
  to stderr when JSON mode is active.
  """

  alias LinearCli.CLI.{Display, Prompt}

  @doc "Returns whether the parsed command options request JSON output."
  def json?(options) when is_map(options), do: Map.get(options, :output, "text") == "json"
  def json?(options) when is_list(options), do: Keyword.get(options, :output, "text") == "json"

  @doc "Prints a successful command result only in JSON mode."
  def success(action, fields, options) when is_map(fields) do
    if json?(options) do
      Display.show(
        Map.merge(%{"action" => to_string(action), "status" => "ok"}, fields),
        %{output: "json"}
      )
    end

    :ok
  end

  @doc "Prints a status line to stderr in JSON mode and stdout otherwise."
  def status(kind, message, options) when kind in [:ok, :say, :warn] do
    device = if json?(options), do: :stderr, else: :stdio

    case kind do
      :ok -> Prompt.ok(message, device)
      :say -> Prompt.say(message, device)
      :warn -> Prompt.warn(message, device)
    end
  end
end
