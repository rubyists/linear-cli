defmodule LinearCli.Rollover.WorkerTest do
  use ExUnit.Case, async: true
  # Same repo/engine LinearCli.ObanRepo would pick at boot for this run
  # (LINEAR_CLI_DB_ADAPTER), not hardcoded - see its moduledoc. Without an
  # explicit engine, Oban.Config.new/1 defaults to Oban.Notifiers.Postgres,
  # which breaks under Oban.Engines.Lite (no Postgrex connection to use).
  use Oban.Testing, repo: LinearCli.ObanRepo.repo(), engine: LinearCli.ObanRepo.oban_engine()

  alias LinearCli.Rollover.Worker

  test "perform/1 runs the configured rollover and succeeds when there's nothing to move" do
    Req.Test.stub(LinearCli.Api, fn conn ->
      Req.Test.json(conn, %{"data" => %{"projects" => %{"nodes" => []}}})
    end)

    assert :ok = perform_job(Worker, %{})
  end

  test "perform/1 surfaces a rollover error as a job failure" do
    # 404, not 500 - 500 is in Req's default transient-retry list and would
    # make this test slow (see LinearCli.ApiTest for the same reasoning).
    Req.Test.stub(LinearCli.Api, fn conn ->
      Plug.Conn.send_resp(conn, 404, "boom")
    end)

    assert {:error, _reason} = perform_job(Worker, %{})
  end
end
