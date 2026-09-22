defmodule Mix.Tasks.Toolchain.CheckTest do
  use ExUnit.Case, async: true

  alias Mix.Tasks.Toolchain.Check

  @mise """
  [tools]
  erlang = "29.1"
  elixir = "1.20.4"
  """

  test "accepts matching workflow pins" do
    assert :ok =
             Check.validate(@mise, [
               {".github/workflows/ci.yaml", workflow("29.1", "1.20.4")}
             ])
  end

  test "reports every workflow pin that differs from mise" do
    assert {:error, message} =
             Check.validate(@mise, [
               {".github/workflows/ci.yaml", workflow("29.0.3", "1.20.3")}
             ])

    assert message =~ "ci.yaml: otp 29.0.3 (expected 29.1)"
    assert message =~ "ci.yaml: elixir 1.20.3 (expected 1.20.4)"
  end

  test "rejects a setup-beam step without both pins" do
    assert {:error, message} =
             Check.validate(@mise, [
               {".github/workflows/ci.yaml", "uses: erlef/setup-beam@v1\notp-version: \"29.1\""}
             ])

    assert message =~ "ci.yaml: elixir missing (expected 1.20.4)"
  end

  defp workflow(otp, elixir) do
    """
    uses: erlef/setup-beam@v1
    otp-version: "#{otp}"
    elixir-version: "#{elixir}"
    """
  end
end
