defmodule LinearCli.ObanRepo.Sqlite do
  @moduledoc """
  SQLite-backed half of Oban's job-table repo - see `LinearCli.ObanRepo` for
  the runtime pick between this and `LinearCli.ObanRepo.Postgres`.
  """

  use Ecto.Repo,
    otp_app: :linear_cli,
    adapter: Ecto.Adapters.SQLite3
end
