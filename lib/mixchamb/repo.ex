defmodule Mixchamb.Repo do
  use Ecto.Repo,
    otp_app: :mixchamb,
    adapter: Ecto.Adapters.Postgres
end
