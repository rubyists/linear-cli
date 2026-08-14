defmodule Mix.Tasks.Burrito.DineinTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Burrito.Dinein

  test "rejects extra positional arguments" do
    assert_raise Mix.Error, "Usage: mix burrito.dinein [--target TARGET]", fn ->
      Dinein.run(["extra"])
    end
  end

  test "detect_target! returns a known supported target for the current host" do
    target = Dinein.detect_target!()
    assert target in ~w[macos_aarch64 linux_x86_64 windows_x86_64]
  end
end
