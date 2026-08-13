defmodule Mix.Tasks.StokowskiTest do
  use ExUnit.Case, async: true

  test "raises when no workflow.yaml is found" do
    File.cd!(System.tmp_dir!(), fn ->
      assert_raise Mix.Error, ~r/No workflow\.yaml at/, fn ->
        Mix.Tasks.Stokowski.run([])
      end
    end)
  end
end
