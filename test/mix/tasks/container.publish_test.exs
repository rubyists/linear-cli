defmodule Mix.Tasks.Container.PublishTest do
  use ExUnit.Case, async: true

  test "requires a TAG argument" do
    assert_raise Mix.Error, "Usage: mix container.publish TAG", fn ->
      Mix.Tasks.Container.Publish.run([])
    end
  end

  test "rejects more than one positional argument" do
    assert_raise Mix.Error, "Usage: mix container.publish TAG", fn ->
      Mix.Tasks.Container.Publish.run(["v1.0.0", "extra"])
    end
  end
end
