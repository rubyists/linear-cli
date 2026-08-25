defmodule LinearCli.Release.BurritoPatches do
  @moduledoc false

  @launcher_path Path.join(["burrito", "src", "erlang_launcher.zig"])
  @wrapper_path Path.join(["burrito", "src", "wrapper.zig"])
  @upstream_pr "https://github.com/burrito-elixir/burrito/pull/235"
  @musl_issue "https://linear.app/the-rubyists/issue/EXT-17"

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

  @legacy_hash_import ~S"""
  const Sha1 = std.crypto.hash.Sha1;
  const Base64 = std.base64.url_safe_no_pad.Encoder;
  """

  @private_hash_import ~S"""
  const Sha1 = std.crypto.hash.Sha1;
  const Sha256 = std.crypto.hash.sha2.Sha256;
  const Base64 = std.base64.url_safe_no_pad.Encoder;
  """

  @legacy_musl_boot ~S"""
      // If on linux, maybe install the musl libc runtime file for our pre-compiled Erlang
      if (comptime IS_LINUX) try maybe_install_musl_runtime(io);

      const self_path = try std.process.executablePathAlloc(io, arena);
  """

  @private_musl_boot ~S"""
      const self_path = try std.process.executablePathAlloc(io, arena);
  """

  @legacy_post_install ~S"""
      } else {
          log.debug("Skipping archive unpacking, this machine already has the app installed!", .{});
      }

      // Clean up older versions
  """

  @private_post_install ~S"""
      } else {
          log.debug("Skipping archive unpacking, this machine already has the app installed!", .{});
      }

      // The downloaded ERTS executables name Burrito's shared /tmp musl loader
      // as their ELF interpreter. Move that trust boundary into a private,
      // verified per-user directory before any release executable is launched.
      if (comptime IS_LINUX) try prepare_musl_runtime(io, arena, install_dir);

      // Clean up older versions
  """

  @legacy_musl_installer ~S"""
  fn maybe_install_musl_runtime(io: Io) !void {
      if (!std.mem.eql(u8, build_options.MUSL_RUNTIME_PATH, "")) {
          // Check if the file was already extracted using std.fs API (cross-platform)
          const file_exists = Io.Dir.cwd().statFile(io, build_options.MUSL_RUNTIME_PATH, .{}) catch null;

          if (file_exists != null) {
              // File exists
              log.debug("The musl runtime file is already present. Continuing.", .{});
              return;
          }

          const file = Io.Dir.cwd().createFile(io, build_options.MUSL_RUNTIME_PATH, .{ .read = true }) catch |e| {
              log.debug("Failed to extract burrito musl runtime: {}", .{e});
              return;
          };
          defer file.close(io);

          const exec_permissions = Io.File.Permissions.fromMode(@intCast(0o754));
          try file.setPermissions(io, exec_permissions);

          const MUSL_RUNTIME_BYTES = @embedFile("musl-runtime.so");
          try file.writePositionalAll(io, MUSL_RUNTIME_BYTES, 0);

          log.debug("Wrote musl runtime file: {s}", .{build_options.MUSL_RUNTIME_PATH});
      }
  }
  """

  @private_musl_installer ~S"""
  fn prepare_musl_runtime(io: Io, arena: std.mem.Allocator, install_dir: []const u8) !void {
      if (std.mem.eql(u8, build_options.MUSL_RUNTIME_PATH, "")) return;

      const linux = std.os.linux;
      const uid = linux.geteuid();
      const private_permissions = Io.File.Permissions.fromMode(@intCast(0o700));
      const runtime_dir_path = try std.fmt.allocPrint(arena, "/tmp/.burrito-musl-{d}", .{uid});

      Io.Dir.cwd().createDir(io, runtime_dir_path, private_permissions) catch |err| switch (err) {
          error.PathAlreadyExists => {},
          else => return err,
      };

      var runtime_dir = try Io.Dir.openDirAbsolute(io, runtime_dir_path, .{
          .iterate = true,
          .follow_symlinks = false,
      });
      defer runtime_dir.close(io);

      try validate_owned_node(runtime_dir.handle, uid, linux.S.IFDIR);
      try runtime_dir.setPermissions(io, private_permissions);

      const musl_bytes = @embedFile("musl-runtime.so");
      var digest: [Sha256.digest_length]u8 = undefined;
      Sha256.hash(musl_bytes, &digest, .{});
      const digest_prefix = std.fmt.bytesToHex(digest[0..16], .lower);
      const loader_name = try std.fmt.allocPrint(arena, "ld-{s}.so", .{digest_prefix});
      const loader_path = try std.fs.path.join(arena, &.{ runtime_dir_path, loader_name });

      install_or_validate_loader(io, &runtime_dir, loader_name, musl_bytes, uid, private_permissions) catch |err| {
          logger.err("Refusing to use an untrusted private musl runtime at {s}: {t}", .{ loader_path, err });
          return err;
      };

      try patch_release_interpreters(io, arena, install_dir, build_options.MUSL_RUNTIME_PATH, loader_path);
      log.debug("Using private musl runtime: {s}", .{loader_path});
  }

  fn validate_owned_node(handle: std.posix.fd_t, uid: std.os.linux.uid_t, expected_type: u16) !void {
      const linux = std.os.linux;
      var info = std.mem.zeroes(linux.Statx);
      const result = linux.statx(
          handle,
          "",
          linux.AT.EMPTY_PATH,
          .{ .TYPE = true, .MODE = true, .UID = true, .NLINK = true },
          &info,
      );

      if (linux.errno(result) != .SUCCESS or
          !info.mask.TYPE or
          !info.mask.MODE or
          !info.mask.UID or
          info.uid != uid or
          info.mode & linux.S.IFMT != expected_type)
      {
          return error.UntrustedMuslRuntime;
      }
  }

  fn install_or_validate_loader(
      io: Io,
      runtime_dir: *Io.Dir,
      loader_name: []const u8,
      expected_bytes: []const u8,
      uid: std.os.linux.uid_t,
      permissions: Io.File.Permissions,
  ) !void {
      if (validate_loader(io, runtime_dir, loader_name, expected_bytes, uid)) return else |err| switch (err) {
          error.FileNotFound => {},
          else => return err,
      }

      var atomic_file = try runtime_dir.createFileAtomic(io, loader_name, .{ .permissions = permissions });
      defer atomic_file.deinit(io);
      try atomic_file.file.writePositionalAll(io, expected_bytes, 0);
      try atomic_file.file.setPermissions(io, permissions);

      atomic_file.link(io) catch |err| switch (err) {
          error.PathAlreadyExists => {},
          else => return err,
      };

      try validate_loader(io, runtime_dir, loader_name, expected_bytes, uid);
  }

  fn validate_loader(
      io: Io,
      runtime_dir: *Io.Dir,
      loader_name: []const u8,
      expected_bytes: []const u8,
      uid: std.os.linux.uid_t,
  ) !void {
      const linux = std.os.linux;
      const file = try runtime_dir.openFile(io, loader_name, .{
          .allow_directory = false,
          .follow_symlinks = false,
      });
      defer file.close(io);

      try validate_owned_node(file.handle, uid, linux.S.IFREG);
      const info = try file.stat(io);

      if (info.permissions.toMode() & 0o777 != 0o700 or info.size != expected_bytes.len) {
          return error.UntrustedMuslRuntime;
      }

      const actual_bytes = try std.heap.page_allocator.alloc(u8, expected_bytes.len);
      defer std.heap.page_allocator.free(actual_bytes);

      if (try file.readPositionalAll(io, actual_bytes, 0) != actual_bytes.len or
          !std.mem.eql(u8, actual_bytes, expected_bytes))
      {
          return error.UntrustedMuslRuntime;
      }
  }

  fn patch_release_interpreters(
      io: Io,
      arena: std.mem.Allocator,
      install_dir: []const u8,
      legacy_path: []const u8,
      private_path: []const u8,
  ) !void {
      var release_dir = try Io.Dir.openDirAbsolute(io, install_dir, .{
          .iterate = true,
          .follow_symlinks = false,
      });
      defer release_dir.close(io);

      var walker = try release_dir.walk(arena);
      defer walker.deinit();

      while (try walker.next(io)) |entry| {
          if (entry.kind == .file) {
              try patch_elf_interpreter(io, entry.dir, entry.basename, legacy_path, private_path);
          }
      }
  }

  fn patch_elf_interpreter(
      io: Io,
      dir: Io.Dir,
      basename: []const u8,
      legacy_path: []const u8,
      private_path: []const u8,
  ) !void {
      const file = try dir.openFile(io, basename, .{
          .allow_directory = false,
          .follow_symlinks = false,
      });
      defer file.close(io);

      const info = try file.stat(io);
      if (info.size < 64 or info.size > std.math.maxInt(usize)) return;

      var header: [64]u8 = undefined;
      if (try file.readPositionalAll(io, &header, 0) != header.len or
          !std.mem.eql(u8, header[0..4], "\x7fELF") or
          header[4] != 2 or
          header[5] != 1)
      {
          return;
      }

      const program_offset = std.mem.readInt(u64, header[32..40], .little);
      const program_entry_size = std.mem.readInt(u16, header[54..56], .little);
      const program_count = std.mem.readInt(u16, header[56..58], .little);

      if (program_count == 0) return;

      if (program_entry_size < 56 or
          program_offset > info.size or
          program_count > (info.size - program_offset) / program_entry_size)
      {
          return error.InvalidElfProgramHeaders;
      }

      for (0..program_count) |index| {
          const entry_offset = program_offset + index * program_entry_size;
          var program_header: [56]u8 = undefined;
          if (try file.readPositionalAll(io, &program_header, entry_offset) != program_header.len) {
              return error.InvalidElfProgramHeaders;
          }

          if (std.mem.readInt(u32, program_header[0..4], .little) != 3) continue;

          const interpreter_offset = std.mem.readInt(u64, program_header[8..16], .little);
          const interpreter_size = std.mem.readInt(u64, program_header[32..40], .little);

          if (interpreter_size == 0 or
              interpreter_size > 4096 or
              interpreter_offset > info.size or
              interpreter_size > info.size - interpreter_offset)
          {
              return error.InvalidElfInterpreter;
          }

          const interpreter = try std.heap.page_allocator.alloc(u8, @intCast(interpreter_size));
          defer std.heap.page_allocator.free(interpreter);

          if (try file.readPositionalAll(io, interpreter, interpreter_offset) != interpreter.len) {
              return error.InvalidElfInterpreter;
          }

          const path_end = std.mem.indexOfScalar(u8, interpreter, 0) orelse
              return error.InvalidElfInterpreter;
          const current_path = interpreter[0..path_end];

          if (std.mem.eql(u8, current_path, private_path)) return;
          if (!std.mem.eql(u8, current_path, legacy_path)) return;
          if (private_path.len + 1 > interpreter.len) return error.MuslRuntimePathTooLong;

          const contents = try std.heap.page_allocator.alloc(u8, @intCast(info.size));
          defer std.heap.page_allocator.free(contents);

          if (try file.readPositionalAll(io, contents, 0) != contents.len) {
              return error.InvalidElfFile;
          }

          const interpreter_start: usize = @intCast(interpreter_offset);
          @memset(contents[interpreter_start .. interpreter_start + interpreter.len], 0);
          @memcpy(contents[interpreter_start .. interpreter_start + private_path.len], private_path);

          var atomic_file = try dir.createFileAtomic(io, basename, .{
              .permissions = info.permissions,
              .replace = true,
          });
          defer atomic_file.deinit(io);
          try atomic_file.file.writePositionalAll(io, contents, 0);
          try atomic_file.file.setPermissions(io, info.permissions);
          try atomic_file.replace(io);
          return;
      }
  }
  """

  @doc false
  def patch_release(%Mix.Release{} = release) do
    launcher_path = Path.join(Mix.Project.deps_path(), @launcher_path)
    wrapper_path = Path.join(Mix.Project.deps_path(), @wrapper_path)
    launcher_source = File.read!(launcher_path)
    wrapper_source = File.read!(wrapper_path)
    patched_launcher = patch_source!(launcher_source)
    patched_wrapper = patch_wrapper_source!(wrapper_source)

    if patched_launcher != launcher_source do
      File.write!(launcher_path, patched_launcher)
      Mix.shell().info("Patched Burrito to inherit stdout when connected to a terminal")
    end

    if patched_wrapper != wrapper_source do
      File.write!(wrapper_path, patched_wrapper)
      Mix.shell().info("Patched Burrito to use a private verified musl runtime")
    end

    release
  end

  @doc false
  def patch_source!(source) when is_binary(source) do
    newline = newline_style(source)
    normalized_source = normalize_newlines(source)
    always_proxy = normalize_newlines(@always_proxy)
    tty_aware_proxy = normalize_newlines(@tty_aware_proxy)
    unconditional_error_join = normalize_newlines(@unconditional_error_join)
    conditional_error_join = normalize_newlines(@conditional_error_join)

    patched =
      cond do
        contains_both?(normalized_source, tty_aware_proxy, conditional_error_join) ->
          normalized_source

        contains_both?(normalized_source, always_proxy, unconditional_error_join) ->
          normalized_source
          |> String.replace(always_proxy, tty_aware_proxy)
          |> String.replace(unconditional_error_join, conditional_error_join)

        true ->
          raise """
          Burrito's stdout launcher no longer matches the expected source. Refusing to
          build without checking whether the terminal inheritance fix is still needed.
          This temporary patch tracks #{@upstream_pr}.
          """
      end

    restore_newlines(patched, newline)
  end

  @doc false
  def patch_wrapper_source!(source) when is_binary(source) do
    newline = newline_style(source)
    normalized_source = normalize_newlines(source)

    legacy_parts = [
      normalize_newlines(@legacy_hash_import),
      normalize_newlines(@legacy_musl_boot),
      normalize_newlines(@legacy_post_install),
      normalize_newlines(@legacy_musl_installer)
    ]

    private_parts = [
      normalize_newlines(@private_hash_import),
      normalize_newlines(@private_musl_boot),
      normalize_newlines(@private_post_install),
      normalize_newlines(@private_musl_installer)
    ]

    private_only_parts = List.delete_at(private_parts, 1)

    patched =
      cond do
        contains_all?(normalized_source, private_parts) and
            contains_none?(normalized_source, legacy_parts) ->
          normalized_source

        contains_all?(normalized_source, legacy_parts) and
            contains_none?(normalized_source, private_only_parts) ->
          Enum.zip_reduce(legacy_parts, private_parts, normalized_source, fn legacy,
                                                                             private,
                                                                             acc ->
            String.replace(acc, legacy, private)
          end)

        true ->
          raise """
          Burrito's musl wrapper no longer matches the expected source. Refusing to
          build without checking whether the private runtime-loader fix is still needed.
          This temporary patch tracks #{@musl_issue}.
          """
      end

    restore_newlines(patched, newline)
  end

  defp contains_both?(source, first, second) do
    String.contains?(source, first) and String.contains?(source, second)
  end

  defp contains_all?(source, snippets), do: Enum.all?(snippets, &String.contains?(source, &1))

  defp contains_none?(source, snippets),
    do: Enum.all?(snippets, &(not String.contains?(source, &1)))

  defp newline_style(source) do
    if String.contains?(source, "\r\n"), do: :crlf, else: :lf
  end

  defp normalize_newlines(source), do: String.replace(source, "\r\n", "\n")

  defp restore_newlines(source, :crlf), do: String.replace(source, "\n", "\r\n")
  defp restore_newlines(source, :lf), do: source
end
