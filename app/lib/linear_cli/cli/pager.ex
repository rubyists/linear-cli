defmodule LinearCli.CLI.Pager do
  @moduledoc """
  Routes text output through `$PAGER` when stdout is a real terminal and
  the content exceeds the terminal height — matching the behavior of
  `git log`, `gh pr view`, and similar CLI tools.

  Paging is skipped when any of the following is true:

  - stdout is not a terminal (`Owl.IO.rows/0` returns `nil`)
  - `$PAGER` is `""` or `"cat"` (user has explicitly disabled paging)
  - The content's line count does not exceed the terminal's row count

  When paging is needed the content is written to a temp file and the
  The pager inherits the terminal's standard streams, so pagers that
  render to standard output (such as `bat`) work as well as interactive
  pagers such as `less`.

  ## Testing

  In tests, `Owl.IO.rows/0` returns `nil` (no real terminal), so paging
  is automatically skipped and `IO.puts/1` is called instead —
  `capture_io` keeps working with no changes to existing tests.

  To exercise the pager path directly, pass injectable overrides:

  - `rows_fn: fn -> 24 end` — simulate a 24-row terminal
  - `shell_fn: fn cmd -> ... end` — capture or mock the shell invocation
  """

  @default_pager "less -FRX"

  @doc """
  Prints `text` directly via `IO.puts/1`, or through `$PAGER` when
  stdout is a terminal and the content exceeds the terminal height.

  `opts` accepts injectable overrides for testing:
  - `:rows_fn` — 0-arity function returning terminal row count or `nil`
    (defaults to `&Owl.IO.rows/0`)
  - `:shell_fn` — 1-arity function receiving the full shell command
    (defaults to a runner that inherits the terminal's standard streams)
  """
  @spec maybe_page(String.t(), map()) :: :ok
  def maybe_page(text, opts \\ %{}) do
    rows_fn = Map.get(opts, :rows_fn, &Owl.IO.rows/0)
    shell_fn = Map.get(opts, :shell_fn, &run_pager/1)
    terminal_rows = rows_fn.()
    pager = resolve_pager()

    if should_page?(text, terminal_rows, pager) do
      invoke_pager(text, pager, shell_fn)
    else
      IO.puts(text)
    end
  end

  defp should_page?(_text, nil, _pager), do: false
  defp should_page?(_text, _rows, nil), do: false
  defp should_page?(text, terminal_rows, _pager), do: count_lines(text) > terminal_rows

  defp resolve_pager do
    case System.get_env("PAGER") do
      nil -> @default_pager
      "" -> nil
      "cat" -> nil
      pager -> pager
    end
  end

  defp count_lines(text) do
    text |> String.trim_trailing("\n") |> String.split("\n") |> length()
  end

  defp invoke_pager(text, pager, shell_fn) do
    path = Path.join(System.tmp_dir!(), "lc-pager-#{System.unique_integer([:positive])}")
    File.write!(path, text)

    try do
      case shell_fn.("#{pager} #{shell_quote(path)}") do
        {_, 0} -> :ok
        _ -> IO.puts(text)
      end
    after
      File.rm(path)
    end

    :ok
  end

  # `System.shell/1` captures a child's stdout. That made pagers such as
  # `bat` appear to succeed while their output was silently discarded.
  defp run_pager(command) do
    shell = System.find_executable("sh") || raise "could not find sh on PATH"

    port =
      Port.open({:spawn_executable, shell}, [
        :nouse_stdio,
        :exit_status,
        args: ["-c", command]
      ])

    receive do
      {^port, {:exit_status, status}} -> {"", status}
    end
  end

  defp shell_quote(path) do
    "'" <> String.replace(path, "'", "'\\''") <> "'"
  end
end
