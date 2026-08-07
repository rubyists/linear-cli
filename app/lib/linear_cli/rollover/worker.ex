defmodule LinearCli.Rollover.Worker do
  @moduledoc """
  Thin `Oban.Worker` wrapper around `LinearCli.Rollover.run/2` - all the
  actual logic lives there so it stays directly callable/testable without
  Oban. Scheduled monthly via `Oban.Plugins.Cron` (`config/config.exs`),
  only running at all in the daemon run mode - see
  `LinearCli.Application`'s `LINEAR_CLI_DAEMON` gate.
  """

  use Oban.Worker

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case LinearCli.Rollover.run(prefix()) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp prefix do
    :linear_cli
    |> Application.fetch_env!(:rollover)
    |> Keyword.fetch!(:prefix)
  end
end
