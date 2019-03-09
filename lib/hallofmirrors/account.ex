defmodule Hallofmirrors.Account do
  use Ecto.Schema
  import Ecto.Changeset

  schema "accounts" do
    field :name, :string
    field :token, :string
    field :twitter_tags, {:array, :string}
    field :email, :string, virtual: true
    field :password, :string, virtual: true
    field :mirroring, :string, virtual: true
    field :last_tweeted_at, :utc_datetime_usec

    belongs_to :instance, Hallofmirrors.Instance
  end

  def create_changeset(struct, %{} = params) do
    struct
    |> cast(params, [:name, :twitter_tags, :email, :password, :mirroring])
    |> validate_required([:name, :email, :password])
    |> put_twitter_tags()
    |> validate_login(params)
    |> put_assoc(:instance, params["instance"])
  end

  def edit_changeset(struct, params) do
    struct
    |> cast(params, [:name, :twitter_tags, :mirroring])
    |> put_twitter_tags()
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
      |> Enum.map(fn tag ->
        tag
        |> String.trim()
        |> String.replace_leading("@", "")
        |> String.downcase()
      end)
      |> Enum.filter(fn x -> x != "" end)
    )
  end
end
