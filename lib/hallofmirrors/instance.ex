defmodule Hallofmirrors.Instance do
  use Ecto.Schema

  alias Hallofmirrors.{
    Instance,
    Repo
  }

  schema "instances" do
    field :url, :string
    field :client_id, :string
    field :client_secret, :string

    has_many :accounts, Hallofmirrors.Account
  end

  def find_or_create(%{url: url} = params) do
    case Repo.get_by(Instance, url: url) do
      %Instance{} = found -> {:ok, found}
      nil -> create(params)
    end
  end

  defp create(%{url: url} = params) do
    entry = %Instance{url: url}

    case Hallofmirrors.Authenticator.create_oauth(entry) do
      {:ok, client_id, client_secret} ->
        entry
        |> Map.put(:client_id, client_id)
        |> Map.put(:client_secret, client_secret)
        |> Repo.insert()

      {:error, body} ->
        {:error, body}
    end
  end
end
