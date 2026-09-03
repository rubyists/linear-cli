defmodule LinearCli.CLI.PagerTest do
  # Not async: some tests set PAGER env var
  use ExUnit.Case

  import ExUnit.CaptureIO

  alias LinearCli.CLI.Pager

  # 50 lines — more than any reasonable terminal height in tests
  @long_text String.duplicate("line\n", 50)
  @short_text "just one line"

  describe "maybe_page/2 - not a TTY" do
    test "prints directly without invoking the pager" do
      {invoked, shell_fn} = spy_shell()

      output =
        capture_io(fn ->
          Pager.maybe_page(@long_text, %{rows_fn: fn -> nil end, shell_fn: shell_fn})
        end)

      assert output =~ "line"
      assert invoked.() == 0
    end
  end

  describe "maybe_page/2 - $PAGER disabled" do
    test "PAGER='' prints directly" do
      with_env("PAGER", "", fn ->
        {invoked, shell_fn} = spy_shell()

        output =
          capture_io(fn ->
            Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
          end)

        assert output =~ "line"
        assert invoked.() == 0
      end)
    end

    test "PAGER=cat prints directly" do
      with_env("PAGER", "cat", fn ->
        {invoked, shell_fn} = spy_shell()

        output =
          capture_io(fn ->
            Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
          end)

        assert output =~ "line"
        assert invoked.() == 0
      end)
    end
  end

  describe "maybe_page/2 - content fits on screen" do
    test "prints directly when line count <= terminal height" do
      {invoked, shell_fn} = spy_shell()

      output =
        capture_io(fn ->
          Pager.maybe_page(@short_text, %{rows_fn: fn -> 40 end, shell_fn: shell_fn})
        end)

      assert output =~ "just one line"
      assert invoked.() == 0
    end

    test "does not page when content is exactly terminal height" do
      # 24 lines, 24-row terminal → fits (not strictly greater)
      text = String.duplicate("x\n", 24)
      {invoked, shell_fn} = spy_shell()

      capture_io(fn ->
        Pager.maybe_page(text, %{rows_fn: fn -> 24 end, shell_fn: shell_fn})
      end)

      assert invoked.() == 0
    end
  end

  describe "maybe_page/2 - content exceeds terminal height" do
    test "invokes the pager" do
      {invoked, shell_fn} = spy_shell()

      capture_io(fn ->
        Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
      end)

      assert invoked.() == 1
    end

    test "uses less -FRX by default (when $PAGER is unset)" do
      with_env("PAGER", nil, fn ->
        commands =
          capture_commands(fn shell_fn ->
            capture_io(fn ->
              Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
            end)
          end)

        assert length(commands) == 1
        assert String.starts_with?(hd(commands), "less -FRX ")
      end)
    end

    test "uses $PAGER when set" do
      with_env("PAGER", "more", fn ->
        commands =
          capture_commands(fn shell_fn ->
            capture_io(fn ->
              Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
            end)
          end)

        assert length(commands) == 1
        assert String.starts_with?(hd(commands), "more ")
      end)
    end

    test "writes content to a temp file and passes the path to the pager" do
      content_received = :erlang.make_ref()

      shell_fn = fn cmd ->
        path = extract_path(cmd)
        send(self(), {content_received, File.read!(path)})
        {"", 0}
      end

      capture_io(fn ->
        Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
      end)

      assert_receive {^content_received, content}
      assert content == @long_text
    end

    test "cleans up the temp file after the pager exits" do
      path_received = :erlang.make_ref()

      shell_fn = fn cmd ->
        send(self(), {path_received, extract_path(cmd)})
        {"", 0}
      end

      capture_io(fn ->
        Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
      end)

      assert_receive {^path_received, path}
      refute File.exists?(path)
    end

    test "cleans up the temp file even when the pager raises" do
      path_received = :erlang.make_ref()

      shell_fn = fn cmd ->
        send(self(), {path_received, extract_path(cmd)})
        raise "pager crashed"
      end

      assert_raise RuntimeError, fn ->
        capture_io(fn ->
          Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
        end)
      end

      assert_receive {^path_received, path}
      refute File.exists?(path)
    end

    test "falls back to IO.puts when the pager exits with non-zero status" do
      shell_fn = fn _cmd -> {"", 127} end

      output =
        capture_io(fn ->
          Pager.maybe_page(@long_text, %{rows_fn: fn -> 5 end, shell_fn: shell_fn})
        end)

      assert output =~ "line"
    end
  end

  # Helpers

  defp spy_shell do
    {:ok, counter} = Agent.start_link(fn -> 0 end)

    shell_fn = fn _cmd ->
      Agent.update(counter, &(&1 + 1))
      {"", 0}
    end

    {fn -> Agent.get(counter, & &1) end, shell_fn}
  end

  defp capture_commands(fun) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    shell_fn = fn cmd ->
      Agent.update(agent, &[cmd | &1])
      {"", 0}
    end

    fun.(shell_fn)
    Agent.get(agent, &Enum.reverse/1)
  end

  # Extracts the temp file path from a single-quoted shell command.
  # Command format: "less -FRX '/tmp/lc-pager-12345'"
  defp extract_path(cmd) do
    [_, quoted] = Regex.run(~r/ '(.+)'$/, cmd)
    quoted
  end

  defp with_env(key, nil, fun) do
    original = System.get_env(key)
    System.delete_env(key)

    try do
      fun.()
    after
      case original do
        nil -> System.delete_env(key)
        v -> System.put_env(key, v)
      end
    end
  end

  defp with_env(key, value, fun) do
    original = System.get_env(key)
    System.put_env(key, value)

    try do
      fun.()
    after
      case original do
        nil -> System.delete_env(key)
        v -> System.put_env(key, v)
      end
    end
  end
end
