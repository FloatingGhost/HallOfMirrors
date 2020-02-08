defmodule Hallofmirrors.Repo.Migrations.AddFilter do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add :must_include, :string, default: ""
    end
  end
end
