defmodule Hallofmirrors.Repo do
  use Ecto.Repo,
    otp_app: :hallofmirrors,
    adapter: Ecto.Adapters.Postgres
end
