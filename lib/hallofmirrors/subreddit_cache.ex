defmodule Hallofmirrors.SubredditLog do
  use Ecto.Schema
  import Ecto.Changeset

  schema "subredditlog" do
    belongs_to :account, Hallofmirrors.Account
    field :post_id, :string
  end

  def changeset(sub, attrs) do
    sub
    |> cast(attrs, [:account_id, :post_id])
  end
end
