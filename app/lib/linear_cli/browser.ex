defmodule LinearCli.Browser do
  @moduledoc false

  @doc """
  Opens `url` in the system's default browser.

  Accepts an injectable `opener` in `opts` (a `url -> :ok | {:error, term()}`
  function) for test doubles — real callers omit it.
  """
  def open_url(url, opts \\ []) do
    opener = Keyword.get(opts, :opener, &default_opener/1)
    opener.(url)
  end

  defp default_opener(url) do
    {cmd, args} =
      case :os.type() do
        {:unix, :darwin} -> {"open", [url]}
        {:win32, _} -> {"cmd", ["/c", "start", url]}
        _ -> {"xdg-open", [url]}
      end

    case System.cmd(cmd, args, stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, code} -> {:error, {:browser_open_failed, code, output}}
    end
  end
end
