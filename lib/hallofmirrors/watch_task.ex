defmodule Hallofmirrors.WatchTask do
  import Ecto.Query
  require Logger

  alias Hallofmirrors.{
    Repo,
    Account
  }

  def start_stream do
    Logger.info("Starting stream...")
    spawn_link(fn ->
      Logger.debug("Link to stream...")
      ExTwitter.stream_filter([follow: get_follows()], :infinity)
      |> Enum.map(&mirror_tweet/1)
    end)
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
    Logger.debug "MIRRORING..."
    from_user =
      tweet
      |> Map.get(:user)
      |> Map.get(:screen_name)
      |> String.downcase()

    tweet
    |> get_photos()
    |> Enum.map(fn entity ->
      url = entity.media_url_https
      filename = get_filename(url)

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} = HTTPoison.get(url)
      :ok = File.write(filename, body)
    end)

    from(account in Account, where: ^from_user in account.twitter_tags)
    |> preload(:instance)
    |> Repo.all()
    |> Task.async_stream(Hallofmirrors.WatchTask, :send_via_account, [tweet])
    |> Enum.into([])

    tweet
    |> get_photos()
    |> Enum.map(fn entity ->
      url = entity.media_url_https
      filename = get_filename(url)
      :ok = File.rm(filename)
    end)
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
      req = HTTPoison.post(upload_url, {:multipart, post_body}, headers)
      case req do
        {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
          {:ok, body} = Jason.decode(body)
          body["id"]
      end
    end)
  end

  defp get_filename(https_url) do
    https_url
    |> String.split("/")
    |> List.last()
    |> (&Path.join("/tmp/", &1)).()
  end

  defp get_photos(%{extended_entities: entities}) when is_list(entities) do
    entities
    |> Map.get(:media, [])
    |> Enum.filter(fn entity -> entity.type == "photo" end)
  end

  defp get_photos(_), do: []
end

