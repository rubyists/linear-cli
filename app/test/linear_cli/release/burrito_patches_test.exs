defmodule LinearCli.Release.BurritoPatchesTest do
  use ExUnit.Case, async: true

  alias LinearCli.Release.BurritoPatches

  test "inherits stdout directly when Burrito is connected to a terminal" do
    launcher_path = Path.expand("../../../deps/burrito/src/erlang_launcher.zig", __DIR__)
    source = File.read!(launcher_path)
    patched = BurritoPatches.patch_source!(source)

    assert patched =~ "const stdout_is_tty = Io.File.stdout().isTty(io) catch false;"
    assert patched =~ "if (builtin.os.tag != .windows and !stdout_is_tty)"
    assert patched =~ "if (copy_thread) |t| t.join();"
    refute patched =~ "if (builtin.os.tag != .windows) {\n        child = try std.process.spawn"
    refute patched =~ "copy_thread.?.join();"
    assert BurritoPatches.patch_source!(patched) == patched
  end

  test "fails closed when Burrito changes the launcher implementation" do
    assert_raise RuntimeError, ~r/no longer matches the expected source/, fn ->
      BurritoPatches.patch_source!("a different upstream implementation")
    end
  end
end
