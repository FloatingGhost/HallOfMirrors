defmodule Hallofmirrors.WatchTask do
  use Task
  import Ecto.Query

  require Logger

  alias Hallofmirrors.{
    Repo,
    Account
  }

  def start_link([func]) do
    Logger.info("Starting #{func}...")
    Task.start_link(__MODULE__, func, [])
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
          |> Enum.filter(fn url ->
            x =
              Repo.get_by(Hallofmirrors.SubredditLog,
                post_id: url,
                account_id: account.id
              )

            is_nil(x)
          end)
          |> (&Enum.uniq(acc ++ &1)).()
        end
      )

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

  def subreddit_loop do
    {:ok, client} = Reddit.Client.login()

    Repo.all(Account)
    |> Enum.map(fn acct ->
      acct = Repo.preload(acct, :instance)
      check_subreddits(client, acct)
    end)

    Process.send_after(self(), :subreddit_loop, 60_000 * 5)
  end

  def start_stream do
    Logger.info("Starting stream...")

    try do
      ExTwitter.stream_filter([follow: get_follows()], :infinity)
      |> Enum.map(&mirror_tweet/1)
    rescue
      _ ->
        Logger.info("Error hit!")
        start_stream()
    end
  end

  defp get_follows do
    Account
    |> Repo.all()
    |> Enum.reduce(
      [],
      fn mirror_acct, acc ->
        acc ++ mirror_acct.twitter_tags
      end
    )
    |> Enum.uniq()
    |> Enum.map(fn username ->
      username
      |> ExTwitter.user()
      |> Map.get(:id)
      |> to_string()
    end)
  end

  defp mirror_tweet(tweet) do
    Logger.debug("MIRRORING...")

    from_user =
      tweet
      |> Map.get(:user)
      |> Map.get(:screen_name)
      |> String.downcase()

    mirror_to =
      from(account in Account, where: ^from_user in account.twitter_tags)
      |> preload(:instance)
      |> Repo.all()

    unless Enum.count(mirror_to) == 0 do
      tweet
      |> get_photos()
      |> Enum.map(fn entity ->
        url = entity.media_url_https
        filename = get_filename(url)

        {:ok, %HTTPoison.Response{status_code: 200, body: body}} = HTTPoison.get(url)
        :ok = File.write(filename, body)
      end)

      mirror_to
      |> Task.async_stream(Hallofmirrors.WatchTask, :send_via_account, [tweet],
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.into([])

      tweet
      |> get_photos()
      |> Enum.map(fn entity ->
        url = entity.media_url_https
        filename = get_filename(url)
        :ok = File.rm(filename)
      end)
    end
  end

  def send_via_account(account, tweet) do
    photo_count =
      tweet
      |> get_photos()
      |> Enum.count()

    unless account.media_only and photo_count == 0 do
      media_ids = upload_media(account, tweet)

      create_url =
        account.instance.url
        |> URI.merge("/api/v1/statuses")
        |> URI.to_string()

      post_body =
        [
          {"status", tweet.text},
          {"visibility", "public"},
          {"sensitive", "false"}
        ] ++ Enum.map(media_ids, fn x -> {"media_ids[]", x} end)

      headers = [{"authorization", account.token}]
      req = HTTPoison.post(create_url, {:multipart, post_body}, headers)

      account
      |> Account.last_tweeted_changeset()
      |> Repo.update()
    end
  end

  defp upload_media(account, %{} = tweet) do
    upload_url =
      account.instance
      |> Map.get(:url)
      |> URI.merge("/api/v1/media")
      |> URI.to_string()

    tweet
    |> get_photos()
    |> Enum.map(fn entity ->
      url = entity.media_url_https
      filename = get_filename(url)
      headers = [{"authorization", account.token}]
      post_body = [{:file, filename}]
      options = [timeout: 30_000, recv_timeout: 30_000]
      req = HTTPoison.post(upload_url, {:multipart, post_body}, headers, options)

      case req do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, body} = Jason.decode(body)
          body["id"]

        {:error, _} ->
          {:error, nil}
      end
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

      {:error, _} ->
        {:error, nil}
    end
  end

  defp get_filename(https_url) do
    https_url
    |> String.split("/")
    |> List.last()
    |> (&Path.join("/tmp/", &1)).()
  end

  defp get_photos(%{extended_entities: %{} = entities}) do
    media_list =
      entities
      |> Map.get(:media, [])

    media_list =
      if is_nil(media_list) do
        []
      else
        media_list
      end

    media_list
    |> Enum.filter(fn entity -> entity.type == "photo" end)
  end

  defp get_photos(_), do: []
end
