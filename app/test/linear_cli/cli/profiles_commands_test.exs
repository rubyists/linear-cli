defmodule LinearCli.CLI.ProfilesCommandsTest do
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  alias LinearCli.Profiles

  setup do
    path = Application.fetch_env!(:linear_cli, :profiles_db_path)
    File.rm(path)
    :ok
  end

  test "JSON profile use and clear each emit one value" do
    {:ok, _profile} = Profiles.create("work", team: "ENG")

    use_output =
      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["profile", "use", "work", "--output", "json"])
      end)

    assert %{"action" => "profile_use", "profile" => "work", "status" => "ok"} =
             Jason.decode!(use_output)

    clear_output =
      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["profile", "clear", "--output", "json"])
      end)

    assert %{"action" => "profile_clear", "status" => "ok"} = Jason.decode!(clear_output)
  end

  test "JSON profile delete emits one value" do
    {:ok, _profile} = Profiles.create("work")

    output =
      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["profile", "delete", "work", "--output", "json"])
      end)

    assert %{"action" => "profile_delete", "profile" => "work", "status" => "ok"} =
             Jason.decode!(output)
  end

  test "JSON profile show returns null when there is no active profile" do
    output =
      capture_io(fn ->
        assert :ok = LinearCli.CLI.main(["profile", "show", "--output", "json"])
      end)

    assert Jason.decode!(output) == nil
  end
end
