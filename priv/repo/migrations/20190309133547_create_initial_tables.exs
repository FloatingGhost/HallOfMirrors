defmodule Hallofmirrors.Repo.Migrations.CreateInitialTables do
  use Ecto.Migration

  def change do
    create table(:instances) do
      add :url, :text, null: false
      add :client_id, :text
      add :client_secret, :text
    end

    create table(:accounts) do
      add :name, :text, null: false
      add :token, :text
      add :twitter_tags, {:array, :string}
      add :instance_id, references(:instances, on_delete: :delete_all)
    end
  end
end
