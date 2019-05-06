defmodule Hallofmirrors.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :name, :string
    field :token, :string
    field :twitter_tags, {:array, :string}
    field :subreddits, {:array, :string}, default: []
    field :email, :string, virtual: true
    field :password, :string, virtual: true
    field :mirroring, :string, virtual: true
    field :last_tweeted_at, :utc_datetime_usec
    field :media_only, :boolean, default: false

    belongs_to :instance, Hallofmirrors.Instance
  end

  def create_changeset(struct, %{} = params) do
    struct
    |> cast(params, [:name, :twitter_tags, :email, :password, :mirroring, :media_only])
    |> validate_required([:name, :email, :password])
    |> put_twitter_tags()
    |> put_subreddits()
    |> validate_login(params)
    |> put_assoc(:instance, params["instance"])
  end

  def edit_changeset(struct, params) do
    struct
    |> cast(params, [:name, :twitter_tags, :mirroring, :media_only])
    |> put_twitter_tags()
    |> put_subreddits()
  end

  def last_tweeted_changeset(struct) do
    struct
    |> Ecto.Changeset.change()
    |> put_change(:last_tweeted_at, DateTime.utc_now())
  end

  defp validate_login(changeset, %{
         "email" => email,
         "password" => password,
         "instance" => instance
       }) do
    case Hallofmirrors.Authenticator.login(instance, email, password) do
      {:ok, token} ->
        changeset
        |> put_change(:token, token)

      {:error, body} ->
        changeset
        |> add_error(:token, body)
    end
  end

  defp put_twitter_tags(%{changes: %{mirroring: mirroring}} = changeset) do
    changeset
    |> put_change(
      :twitter_tags,
      mirroring
      |> String.split(" ")
      |> Enum.filter(fn tag -> String.starts_with?(tag, "@") end)
      |> Enum.map(fn tag ->
        tag
        |> String.trim()
        |> String.replace_leading("@", "")
        |> String.downcase()
      end)
      |> Enum.filter(fn x -> x != "" end)
    )
  end

  defp put_subreddits(%{changes: %{mirroring: mirroring}} = changeset) do
    changeset
    |> put_change(
      :subreddits,
      mirroring
      |> String.split(" ")
      |> Enum.filter(fn tag -> String.starts_with?(tag, "r/") end)
      |> Enum.map(fn tag ->
        tag
        |> String.trim()
        |> String.replace_leading("r/", "")
        |> String.downcase()
      end)
      |> Enum.filter(fn x -> x != "" end)
    )
  end
end
