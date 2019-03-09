defmodule Hallofmirrors.StreamWatcher do
  use GenServer
  require Logger
  import Ecto.Query

  alias Hallofmirrors.{
    Repo,
    Account
  }

  def start_link(_) do
    case GenServer.start_link(__MODULE__, nil, name: {:global, __MODULE__}) do
      {:ok, pid} ->
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        Process.link(pid)
        {:ok, pid}
      :ignore ->
        :ignore
    end
  end

  def init(_) do  
    pid = start_stream()
    {:ok, pid}
  end

  def handle_cast({:restart}, pid) do
    Logger.debug("Restarting stream...")
    ExTwitter.stream_control(pid, :stop)
    pid = start_stream()
    {:noreply, pid}
  end

  def restart(pid) do
    GenServer.cast(pid, {:restart})
  end

  defp start_stream do
    spawn(fn ->
      Logger.debug("Spawning...")
      stream = ExTwitter.stream_filter(follow: get_follows(), timeout: :infinity)
      for tweet <- stream do
        mirror_tweet(tweet)
      end          
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
    |> Task.async_stream(Hallofmirrors.StreamWatcher, :send_via_account, [tweet])
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

  defp get_photos(%{entities: entities}) do 
    entities
    |> Map.get(:media, [])
    |> Enum.filter(fn entity -> entity.type == "photo" end)
  end

  defp get_photos(_), do: []
end 
