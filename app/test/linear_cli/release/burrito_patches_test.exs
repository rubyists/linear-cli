defmodule LinearCli.Release.BurritoPatchesTest do
  use ExUnit.Case, async: true

  alias LinearCli.Release.BurritoPatches

  @unpatched_launcher ~S"""
      // On Unix: pipe child stdout through us so we can detect EPIPE from
      // the downstream consumer (e.g. `app cmd | head -5`). When the consumer
      // exits and breaks the pipe, the copy thread kills the BEAM child.
      // On Windows: inherit stdout directly — std.c.read blocks on Windows
      // pipes, and the EPIPE group-leader hang is Unix-specific anyway.
      var child: std.process.Child = undefined;
      var copy_thread: ?std.Thread = null;

      if (builtin.os.tag != .windows) {
          // The rest of the spawn block is irrelevant to the source patch.
      }

      const term = if (builtin.os.tag != .windows)
          child.wait(io) catch {
              copy_thread.?.join();
              std.process.exit(0);
          }
  """

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

  test "moves the Linux musl runtime into a verified per-user directory" do
    wrapper_path = Path.expand("../../../deps/burrito/src/wrapper.zig", __DIR__)
    source = File.read!(wrapper_path)
    patched = BurritoPatches.patch_wrapper_source!(source)

    assert patched =~ ~s|"/tmp/.burrito-musl-{d}"|
    assert patched =~ "linux.geteuid()"
    assert patched =~ ".follow_symlinks = false"
    assert patched =~ "info.uid != uid"
    assert patched =~ "!std.mem.eql(u8, actual_bytes, expected_bytes)"
    assert patched =~ "runtime_dir.createFileAtomic"
    assert patched =~ "atomic_file.link(io)"
    assert patched =~ "patch_release_interpreters"
    assert patched =~ ~s|!std.mem.eql(u8, header[0..4], "\\x7fELF")|
    assert patched =~ "std.mem.eql(u8, current_path, legacy_path)"
    assert patched =~ "atomic_file.replace(io)"
    assert patched =~ ~s|".burrito-musl-interpreters-v1"|
    assert patched =~ ~s|"v1\\n{s}\\n{s}\\n"|
    assert patched =~ "interpreter_marker_is_valid"
    assert patched =~ "atomic_marker.replace(io)"
    assert patched =~ "info.permissions.toMode() & 0o777 != 0o600"
    refute patched =~ "fn maybe_install_musl_runtime"
    refute patched =~ "createFile(io, build_options.MUSL_RUNTIME_PATH"
    assert BurritoPatches.patch_wrapper_source!(patched) == patched
  end

  test "fails closed when Burrito changes the launcher implementation" do
    assert_raise RuntimeError, ~r/no longer matches the expected source/, fn ->
      BurritoPatches.patch_source!("a different upstream implementation")
    end
  end

  test "fails closed when Burrito changes or partially patches the musl implementation" do
    assert_raise RuntimeError, ~r/musl wrapper no longer matches the expected source/, fn ->
      BurritoPatches.patch_wrapper_source!("a different upstream implementation")
    end

    wrapper_path = Path.expand("../../../deps/burrito/src/wrapper.zig", __DIR__)

    partially_patched =
      wrapper_path
      |> File.read!()
      |> String.replace(
        "const Sha1 = std.crypto.hash.Sha1;\n",
        "const Sha1 = std.crypto.hash.Sha1;\nconst Sha256 = std.crypto.hash.sha2.Sha256;\n"
      )

    assert_raise RuntimeError, ~r/musl wrapper no longer matches the expected source/, fn ->
      BurritoPatches.patch_wrapper_source!(partially_patched)
    end
  end

  test "matches LF Burrito source when the release hook was checked out with CRLF" do
    patch_module_path = Path.expand("../../../release/burrito_patches.exs", __DIR__)

    crlf_module_source =
      patch_module_path
      |> File.read!()
      |> String.replace(
        "defmodule LinearCli.Release.BurritoPatches do",
        "defmodule LinearCli.Release.BurritoPatchesCRLF do"
      )
      |> String.replace(~r/\r?\n/, "\r\n")

    [{crlf_module, _bytecode}] = Code.compile_string(crlf_module_source)
    patched = crlf_module.patch_source!(@unpatched_launcher)

    assert patched =~ "const stdout_is_tty = Io.File.stdout().isTty(io) catch false;"
    assert patched =~ "if (builtin.os.tag != .windows and !stdout_is_tty)"
    refute patched =~ "copy_thread.?.join();"
  end

  test "preserves CRLF when Burrito's source uses CRLF" do
    source = String.replace(@unpatched_launcher, "\n", "\r\n")
    patched = BurritoPatches.patch_source!(source)

    assert patched =~ "\r\n"
    refute patched =~ ~r/(?<!\r)\n/
    assert BurritoPatches.patch_source!(patched) == patched
  end

  test "preserves CRLF while patching Burrito's musl wrapper" do
    wrapper_path = Path.expand("../../../deps/burrito/src/wrapper.zig", __DIR__)
    source = wrapper_path |> File.read!() |> String.replace(~r/\r?\n/, "\r\n")
    patched = BurritoPatches.patch_wrapper_source!(source)

    assert patched =~ "\r\n"
    refute patched =~ ~r/(?<!\r)\n/
    assert patched =~ ~s|"/tmp/.burrito-musl-{d}"|
    assert BurritoPatches.patch_wrapper_source!(patched) == patched
  end
end
