defmodule HallofmirrorsWeb.AccountController do
  use HallofmirrorsWeb, :controller

  alias Hallofmirrors.{
    Instance,
    Account,
    Repo,
    WatchTask
  }

  def create(conn, %{"instance_url" => url} = params) do
    {:ok, instance} = Instance.find_or_create(%{url: url})

    params =
      params
      |> Map.put("instance", instance)

    changeset = Account.create_changeset(%Account{}, params)

    if changeset.valid? do
      {:ok, _account} = Repo.insert(changeset)
      {:ok, pid} = Hallofmirrors.StreamWatcher.start_link([])
      Hallofmirrors.StreamWatcher.restart(pid)
      redirect(conn, to: "/")
    end
  end

  def edit_form(conn, %{"id" => id}) do
    with %Account{} = account <- Repo.get(Account, id) do
      render(conn, "edit_account.html", account: account)
    end
  end

  def edit(conn, %{"id" => id} = params) do
    with %Account{} = account <- Repo.get(Account, id) do
      changeset = Account.edit_changeset(account, params)
      {:ok, _} = Repo.update(changeset)
      {:ok, pid} = Hallofmirrors.StreamWatcher.start_link([])
      Hallofmirrors.StreamWatcher.restart(pid)
      redirect(conn, to: "/")
    end
  end

  def mirror_form(conn, %{"id" => id}) do
    with %Account{} = account <- Repo.get(Account, id) do
      render(conn, "manual_mirror.html", account: account)
    end
  end

  def mirror(conn, %{"id" => id, "tweet_id" => tweet_id}) do
    IO.puts(tweet_id)
    with %Account{} = account <- Repo.get(Account, id),
	 %Account{} = account <- Repo.preload(account, [:instance]),
         %{} = tweet <- ExTwitter.show(tweet_id) do
	
      WatchTask.download_photos(tweet)
      WatchTask.send_via_account(account, tweet)
      WatchTask.delete_photos(tweet)
      redirect(conn, to: "/accounts/#{id}")
    end
  end

  def delete(conn, %{"id" => id}) do
    with %Account{} = account <- Repo.get(Account, id) do
      Repo.delete(account)
      redirect(conn, to: "/")
    end
  end
end
