defmodule LinearCliTest do
  use ExUnit.Case
  doctest LinearCli

  test "greets the world" do
    assert LinearCli.hello() == :world
  end
end
