defmodule Hallofmirrors.Repo.Migrations.AddLastTweetedAt do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :last_tweeted_at, :utc_datetime
    end
  end
end
