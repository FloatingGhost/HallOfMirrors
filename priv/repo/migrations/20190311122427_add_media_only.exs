defmodule Hallofmirrors.Repo.Migrations.AddMediaOnly do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :media_only, :boolean, default: false
    end
  end
end
