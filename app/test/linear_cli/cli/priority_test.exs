defmodule LinearCli.CLI.PriorityTest do
  use ExUnit.Case, async: true

  alias LinearCli.CLI.Priority

  describe "parse/1" do
    test "maps none to 0" do
      assert {:ok, 0} = Priority.parse("none")
    end

    test "maps urgent to 1" do
      assert {:ok, 1} = Priority.parse("urgent")
    end

    test "maps high to 2" do
      assert {:ok, 2} = Priority.parse("high")
    end

    test "maps medium to 3" do
      assert {:ok, 3} = Priority.parse("medium")
    end

    test "maps low to 4" do
      assert {:ok, 4} = Priority.parse("low")
    end

    test "matching is case-insensitive" do
      assert {:ok, 1} = Priority.parse("URGENT")
      assert {:ok, 2} = Priority.parse("High")
      assert {:ok, 3} = Priority.parse("MEDIUM")
      assert {:ok, 4} = Priority.parse("Low")
      assert {:ok, 0} = Priority.parse("None")
    end

    test "returns error for unknown priority" do
      assert {:error, message} = Priority.parse("critical")
      assert message =~ "unknown priority \"critical\""
      assert message =~ "must be one of:"
    end

    test "error message lists all valid values" do
      assert {:error, message} = Priority.parse("bad")
      assert message =~ "high"
      assert message =~ "low"
      assert message =~ "medium"
      assert message =~ "none"
      assert message =~ "urgent"
    end
  end
end
