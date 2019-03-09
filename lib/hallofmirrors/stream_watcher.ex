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
    pid = start_stream_link()
    {:ok, pid}
  end

  def handle_cast({:restart}, pid) do
    Logger.debug("Restarting stream...")
    ExTwitter.stream_control(pid, :stop)
    pid = start_stream_link()
    {:noreply, pid}
  end

  def restart(pid) do
    GenServer.cast(pid, {:restart})
  end

  defp start_stream_link do
    Task.start_link(Hallofmirrors.WatchTask, :start_stream, [])
  end

end 
