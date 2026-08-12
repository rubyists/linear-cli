defmodule Mix.Tasks.Container.BuildTest do
  use ExUnit.Case, async: true

  test "requires a TAG argument" do
    assert_raise Mix.Error, "Usage: mix container.build TAG [--push]", fn ->
      Mix.Tasks.Container.Build.run([])
    end
  end

  test "rejects more than one positional argument" do
    assert_raise Mix.Error, "Usage: mix container.build TAG [--push]", fn ->
      Mix.Tasks.Container.Build.run(["v1.0.0", "extra"])
    end
  end
end
