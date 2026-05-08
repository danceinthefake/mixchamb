defmodule Mixwave.Repo do
  use Ecto.Repo,
    otp_app: :mixwave,
    adapter: Ecto.Adapters.Postgres
end
