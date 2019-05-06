defmodule Hallofmirrors.Repo.Migrations.AddSubredditsColumn do
  use Ecto.Migration

  def change do
    alter table(:accounts) do
      add(:subreddits, {:array, :string})
    end
  end
end
