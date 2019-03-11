defmodule Hallofmirrors.WatchTask do
  use Task
  import Ecto.Query
  
  require Logger

  alias Hallofmirrors.{
    Repo,
    Account
  }

  def start_link(_) do
    Task.start_link(__MODULE__, :start_stream, [])
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
        |> Task.async_stream(Hallofmirrors.WatchTask, :send_via_account, [tweet], timeout: 60_000, on_timeout: :kill_task)
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

  defp upload_media(account, tweet) do
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
