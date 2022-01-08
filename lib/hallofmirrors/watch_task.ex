defmodule Hallofmirrors.WatchTask do
  use Task
  import Ecto.Query

  require Logger

  @http_options [ssl: [{:versions, [:"tlsv1.2"]}]]

  alias Hallofmirrors.{
    Repo,
    Account
  }

  def start_link(_) do
    Logger.info("Starting twitter mirror...")
    Task.start_link(__MODULE__, :start_stream, [])
  end

  def start_stream do
    Logger.info("Starting stream...")

    try do
      ExTwitter.stream_filter([follow: get_follows()], :infinity)
      |> Enum.map(&mirror_tweet/1)
    rescue
      e ->
        Logger.info("Error hit!")
        Logger.info(e)
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
      |> Enum.filter(fn account -> String.contains?(tweet.text, account.must_include) end)
    unless Enum.count(mirror_to) == 0 do
      download_photos(tweet)

      mirror_to
      |> Task.async_stream(Hallofmirrors.WatchTask, :send_via_account, [tweet],
        timeout: 60_000,
        on_timeout: :kill_task
      )
      |> Enum.into([])

      delete_photos(tweet)
    end
  end

  def download_photos(tweet) do
    IO.inspect(tweet)
    tweet
    |> get_photos()
    |> Enum.map(fn entity ->
      url = get_url(entity)
      filename = get_filename(url)

      {:ok, %HTTPoison.Response{status_code: 200, body: body}} = HTTPoison.get(url, [], @http_options)
      :ok = File.write(filename, body)
    end)
  end

  def delete_photos(tweet) do
    tweet
    |> get_photos()
    |> Enum.map(fn entity ->
      url = get_url(entity)
      filename = get_filename(url)
      :ok = File.rm(filename)
    end)
  end

  def get_url(entity) do
    case entity.type do
      "photo" ->
        entity.media_url_https

      "video" ->
        %{url: u} =
          entity.raw_data.video_info.variants
          |> Enum.filter(fn x -> Map.has_key?(x, :bitrate) end)
          |> List.first()

        u
        |> String.split("?")
        |> List.first()
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

      from_user = tweet
      |> Map.get(:user)
      |> Map.get(:screen_name)
      |> String.downcase()


      post_body =
        [
          {"status", "#{from_user}: #{tweet.text}"},
          {"visibility", "unlisted"},
          {"sensitive", "false"}
        ] ++ Enum.map(media_ids, fn x -> {"media_ids[]", x} end)

      headers = [{"authorization", account.token}]
      HTTPoison.post(create_url, {:multipart, post_body}, headers, @http_options)

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
      url = get_url(entity)
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
    |> Enum.filter(fn entity -> Enum.member?(["photo", "video"], entity.type) end)
  end

  defp get_photos(_), do: []
end
