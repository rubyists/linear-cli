defmodule RecoverReleaseTest do
  use ExUnit.Case, async: true

  # ci/recover_release.sh re-dispatches a release whose release-PR merge run
  # failed. 2.10.0 and 2.11.0 both failed validation on that run, which left
  # release-please aborting on every later push until the release was
  # dispatched by hand.

  @script Path.expand("../ci/recover_release.sh", __DIR__)

  @fake_gh """
  #!/bin/sh
  printf '%s\\n' "$*" >> "$FAKE_GH_LOG"
  case "$1 $2" in
      "release view")
          [ "$FAKE_RELEASE_EXISTS" = "yes" ] && exit 0
          exit 1
          ;;
      "run list")
          [ -n "$FAKE_RUN_LIST_FAILS" ] && exit 1
          printf '%s\\n' "${FAKE_IN_FLIGHT:-0}"
          ;;
      "workflow run")
          [ -n "$FAKE_DISPATCH_FAILS" ] && exit 1
          exit 0
          ;;
  esac
  """

  setup do
    dir = tmp_dir!()
    bin = Path.join(dir, "bin")
    File.mkdir_p!(bin)
    gh = Path.join(bin, "gh")
    File.write!(gh, @fake_gh)
    File.chmod!(gh, 0o755)

    manifest = Path.join(dir, "manifest.json")
    File.write!(manifest, ~s({".": "2.11.0"}\n))

    %{dir: dir, bin: bin, manifest: manifest, log: Path.join(dir, "gh.log")}
  end

  test "does nothing when the manifest version is released", ctx do
    assert {output, 0} = run(ctx, [{"FAKE_RELEASE_EXISTS", "yes"}])
    assert output =~ "Release v2.11.0 exists; nothing to recover"
    assert gh_calls(ctx) == ["release view v2.11.0 --json tagName"]
  end

  test "dispatches the release run when the version was never released", ctx do
    assert {output, 0} = run(ctx)
    assert output =~ "::warning::Release v2.11.0 was missing; dispatched main.yaml"
    assert List.last(gh_calls(ctx)) == "workflow run main.yaml --ref main"
  end

  test "waits while a release-capable run is still in progress", ctx do
    assert {output, 0} = run(ctx, [{"FAKE_IN_FLIGHT", "1"}])
    assert output =~ "1 release-capable run(s) are in progress; not dispatching"
    refute Enum.any?(gh_calls(ctx), &String.starts_with?(&1, "workflow run"))
  end

  test "fails when the dispatch fails", ctx do
    assert {output, 1} = run(ctx, [{"FAKE_DISPATCH_FAILS", "1"}])
    assert output =~ "ERROR: release v2.11.0 is missing and dispatching main.yaml failed"
  end

  test "fails when runs cannot be listed", ctx do
    assert {output, 1} = run(ctx, [{"FAKE_RUN_LIST_FAILS", "1"}])
    assert output =~ "ERROR: unable to list main.yaml runs"
  end

  test "fails when the manifest has no version", ctx do
    File.write!(ctx.manifest, "{}\n")

    assert {output, 1} = run(ctx)
    assert output =~ "ERROR: unable to read the version from"
  end

  defp run(ctx, env \\ []) do
    base = [
      {"PATH", "#{ctx.bin}:#{System.get_env("PATH")}"},
      {"FAKE_GH_LOG", ctx.log},
      {"RELEASE_MANIFEST", ctx.manifest}
    ]

    System.cmd(@script, [], env: base ++ env, stderr_to_stdout: true, cd: ctx.dir)
  end

  defp gh_calls(ctx) do
    case File.read(ctx.log) do
      {:ok, log} -> String.split(log, "\n", trim: true)
      {:error, :enoent} -> []
    end
  end

  defp tmp_dir! do
    nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    path = Path.join(System.tmp_dir!(), "linear_cli_recover_release_#{nonce}")
    File.mkdir!(path)
    on_exit(fn -> File.rm_rf!(path) end)
    path
  end
end
