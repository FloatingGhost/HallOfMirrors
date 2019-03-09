defmodule HallofmirrorsWeb.AccountController do
  use HallofmirrorsWeb, :controller

  alias Hallofmirrors.{
    Instance,
    Account,
    Repo
  }

  def create(conn, %{"instance_url" => url} = params) do
    {:ok, instance} = Instance.find_or_create(%{url: url})

    params = 
      params
      |> Map.put("instance", instance)

    changeset = Account.create_changeset(%Account{}, params)

    if changeset.valid? do
      {:ok, account} = Repo.insert(changeset)
      redirect(conn, to: "/")
    end
  end
end
