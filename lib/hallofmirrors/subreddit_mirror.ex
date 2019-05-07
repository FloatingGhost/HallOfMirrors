defmodule Hallofmirrors.SubredditMirror do
  use Task
  require Logger

  alias Hallofmirrors.{
    Repo,
    Account,
    SubredditLog
  }

  def start_link(_) do
    Logger.info("Starting subreddit mirror...")
    Task.start_link(__MODULE__, :check_all, [])
  end

  def check_all do
    {:ok, client} = Reddit.Client.login()

    Repo.all(Account)
    |> Enum.map(fn acct ->
      acct = Repo.preload(acct, :instance)
      check_subreddits(client, acct)
    end)
  end

  def check_subreddits(client, %{subreddits: subs} = account) do
    images =
      Enum.reduce(
        subs,
        [],
        fn sub, acc ->
          {:ok, %{body: %{"data" => %{"children" => resp}}}} =
            {:ok, resp} =
            client
            |> Reddit.Subreddit.hot_posts(sub)

          resp
          |> Enum.map(fn %{"data" => %{"url" => url}} -> url end)
          |> Enum.filter(fn url ->
            ["png", "gif", "jpg"]
            |> Enum.any?(fn ext -> String.ends_with?(url, ext) end)
          end)
          |> (&Enum.uniq(acc ++ &1)).()
        end
      )
      |> Enum.filter(fn url ->
       x = Repo.get_by(SubredditLog, post_id: url,)
       is_nil(x)
      end)

    images
    |> Enum.map(fn image ->
      original_url = image
      filename = get_filename(image)
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} = HTTPoison.get(image)
      :ok = File.write(filename, body)

      image = upload_media(account, image)

      create_url =
        account.instance.url
        |> URI.merge("/api/v1/statuses")
        |> URI.to_string()

      post_body =
        [
          {"status", "."},
          {"visibility", "public"},
          {"sensitive", "false"}
        ] ++ Enum.map([image], fn x -> {"media_ids[]", x} end)

      headers = [{"authorization", account.token}]
      req = HTTPoison.post(create_url, {:multipart, post_body}, headers)

      account
      |> Account.last_tweeted_changeset()
      |> Repo.update()

      log =
        Hallofmirrors.SubredditLog.changeset(
          %Hallofmirrors.SubredditLog{},
          %{account_id: account.id, post_id: original_url}
        )

      Repo.insert(log)
      File.rm(filename)
    end)
  end

  defp upload_media(account, url) when is_binary(url) do
    upload_url =
      account.instance
      |> Map.get(:url)
      |> URI.merge("/api/v1/media")
      |> URI.to_string()

    filename = get_filename(url)
    headers = [{"authorization", account.token}]
    post_body = [{:file, filename}]
    options = [timeout: 30_000, recv_timeout: 30_000]
    req = HTTPoison.post(upload_url, {:multipart, post_body}, headers, options)

    case req do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        {:ok, body} = Jason.decode(body)
        body["id"]

      _other ->
        {:error, nil}
    end
  end

  defp get_filename(https_url) do
    https_url
    |> String.split("/")
    |> List.last()
    |> (&Path.join("/tmp/", &1)).()
  end
end
