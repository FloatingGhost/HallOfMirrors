defmodule HallofmirrorsWeb.PageController do
  use HallofmirrorsWeb, :controller

  import Ecto.Query

  def index(conn, _params) do
    accounts = Hallofmirrors.Repo.all(Hallofmirrors.Account)

    render(conn, "index.html", accounts: accounts)
  end
end
