defmodule LinearCli.CLI.MissingApiKeyTest do
  # async: false - unsets the real (VM-global, not per-process)
  # LINEAR_API_KEY env var, same reason/pattern as LinearCli.ApiTest.
  use ExUnit.Case, async: false
  import ExUnit.CaptureIO

  test "a missing LINEAR_API_KEY gives a clear message and exits 78, not a raw Ash dump" do
    previous = System.get_env("LINEAR_API_KEY")
    System.delete_env("LINEAR_API_KEY")
    on_exit(fn -> previous && System.put_env("LINEAR_API_KEY", previous) end)

    test_pid = self()
    halt = fn code -> send(test_pid, {:halted, code}) end

    output = capture_io(:stderr, fn -> LinearCli.CLI.main(["whoami"], halt) end)

    assert_received {:halted, 78}
    assert output =~ "LINEAR_API_KEY is not set."
    assert output =~ "https://linear.app/settings/account/security"
    refute output =~ "What the heck is this?"
    refute output =~ "Ash.Error"
  end
end
