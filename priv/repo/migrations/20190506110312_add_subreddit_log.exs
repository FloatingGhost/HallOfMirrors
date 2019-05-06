defmodule Hallofmirrors.Repo.Migrations.AddSubredditLog do
  use Ecto.Migration

  def change do
    create table(:subredditlog) do
      add :account_id, references(:accounts)
      add :post_id, :string
    end

    create unique_index(:subredditlog, [:account_id, :post_id])
  end
end
