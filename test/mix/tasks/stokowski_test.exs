defmodule Mix.Tasks.StokowskiTest do
  use ExUnit.Case, async: true

  test "raises when no workflow.yaml is found" do
    in_tmp_dir(fn ->
      assert_raise Mix.Error, ~r/No workflow\.yaml at/, fn ->
        Mix.Tasks.Stokowski.run([])
      end
    end)
  end

  test "raises when tracker.api_key is a bare literal" do
    in_tmp_dir(fn ->
      File.write!("workflow.yaml", """
      tracker:
        api_key: "lin_api_totally_real"
      """)

      assert_raise Mix.Error, ~r/is a bare literal key/, fn ->
        Mix.Tasks.Stokowski.run([])
      end
    end)
  end

  # Each test gets its own directory rather than sharing System.tmp_dir!()
  # directly - both tests run async and would otherwise race on the same
  # workflow.yaml. A cryptographic nonce avoids collisions across BEAM VM
  # restarts (unlike System.unique_integer/1 which resets each run).
  defp in_tmp_dir(fun) do
    nonce = :crypto.strong_rand_bytes(16) |> Base.url_encode64(padding: false)
    dir = Path.join(System.tmp_dir!(), "stokowski_test_#{nonce}")
    File.mkdir!(dir)

    try do
      File.cd!(dir, fun)
    after
      File.rm_rf!(dir)
    end
  end
end
