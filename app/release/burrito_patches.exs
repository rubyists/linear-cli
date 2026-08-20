defmodule LinearCli.Release.BurritoPatches do
  @moduledoc false

  @launcher_path Path.join(["burrito", "src", "erlang_launcher.zig"])
  @upstream_pr "https://github.com/burrito-elixir/burrito/pull/235"

  @always_proxy ~S"""
      // On Unix: pipe child stdout through us so we can detect EPIPE from
      // the downstream consumer (e.g. `app cmd | head -5`). When the consumer
      // exits and breaks the pipe, the copy thread kills the BEAM child.
      // On Windows: inherit stdout directly — std.c.read blocks on Windows
      // pipes, and the EPIPE group-leader hang is Unix-specific anyway.
      var child: std.process.Child = undefined;
      var copy_thread: ?std.Thread = null;

      if (builtin.os.tag != .windows) {
  """

  @tty_aware_proxy ~S"""
      // On Unix, when stdout is NOT a tty (piped/redirected): pipe child
      // stdout through us so we can detect EPIPE from the downstream consumer
      // (e.g. `app cmd | head -5`). When the consumer exits and breaks the
      // pipe, the copy thread kills the BEAM child.
      //
      // When stdout IS a tty, inherit it directly: the BEAM's prim_tty needs
      // both stdin and stdout to be TTYs for raw mode, ANSI detection, and
      // keyboard input to work (interactive/TUI apps), and the EPIPE hang
      // cannot occur on a tty.
      //
      // On Windows: always inherit stdout — std.c.read blocks on Windows
      // pipes, and the EPIPE group-leader hang is Unix-specific anyway.
      const stdout_is_tty = Io.File.stdout().isTty(io) catch false;

      var child: std.process.Child = undefined;
      var copy_thread: ?std.Thread = null;

      if (builtin.os.tag != .windows and !stdout_is_tty) {
  """

  @unconditional_error_join ~S"""
          child.wait(io) catch {
              copy_thread.?.join();
              std.process.exit(0);
          }
  """

  @conditional_error_join ~S"""
          child.wait(io) catch {
              if (copy_thread) |t| t.join();
              std.process.exit(0);
          }
  """

  @doc false
  def patch_release(%Mix.Release{} = release) do
    launcher_path = Path.join(Mix.Project.deps_path(), @launcher_path)
    source = File.read!(launcher_path)
    patched = patch_source!(source)

    if patched != source do
      File.write!(launcher_path, patched)
      Mix.shell().info("Patched Burrito to inherit stdout when connected to a terminal")
    end

    release
  end

  @doc false
  def patch_source!(source) when is_binary(source) do
    cond do
      contains_both?(source, @tty_aware_proxy, @conditional_error_join) ->
        source

      contains_both?(source, @always_proxy, @unconditional_error_join) ->
        source
        |> String.replace(@always_proxy, @tty_aware_proxy)
        |> String.replace(@unconditional_error_join, @conditional_error_join)

      true ->
        raise """
        Burrito's stdout launcher no longer matches the expected source. Refusing to
        build without checking whether the terminal inheritance fix is still needed.
        This temporary patch tracks #{@upstream_pr}.
        """
    end
  end

  defp contains_both?(source, first, second) do
    String.contains?(source, first) and String.contains?(source, second)
  end
end
