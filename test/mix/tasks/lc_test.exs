defmodule Mix.Tasks.LcTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Lc

  test "forwards lc arguments unchanged through the app project" do
    caller = self()

    command = fn executable, args, opts ->
      send(caller, {:command, executable, args, opts})
      0
    end

    halt = fn status -> flunk("unexpected halt with status #{status}") end

    assert :ok = Lc.run(["issue", "create", "title with spaces"], command, halt)

    assert_receive {:command, "mix",
                    [
                      "run",
                      "-e",
                      "LinearCli.CLI.main(System.argv())",
                      "--",
                      "issue",
                      "create",
                      "title with spaces"
                    ], opts}

    assert opts[:cd] == Path.expand("app")
    assert opts[:env] == [{"MIX_QUIET", "1"}]
    assert opts[:stdio] == :inherit
  end

  test "preserves the child lc exit status" do
    caller = self()
    command = fn _executable, _args, _opts -> 66 end
    halt = fn status -> send(caller, {:halt, status}) end

    assert :ok = Lc.run(["issue", "view", "missing"], command, halt)
    assert_receive {:halt, 66}
  end

  test "returns the exact exit status from an inherited-stdio child" do
    assert 37 ==
             Lc.run_child("sh", ["-c", "exit 37"],
               cd: File.cwd!(),
               env: [],
               stdio: :inherit
             )
  end
end
