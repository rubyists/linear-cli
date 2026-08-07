defmodule LinearCli.ObanRepo.Postgres do
  @moduledoc """
  Postgres-backed half of Oban's job-table repo - see `LinearCli.ObanRepo`
  for the runtime pick between this and `LinearCli.ObanRepo.Sqlite`.
  """

  use Ecto.Repo,
    otp_app: :linear_cli,
    adapter: Ecto.Adapters.Postgres
end
