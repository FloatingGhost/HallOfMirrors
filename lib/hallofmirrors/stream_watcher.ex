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
    {:ok, Hallofmirrors.WatchTask.start_stream()}
  end

  def handle_cast({:restart}, state) do
    Logger.debug("Restarting stream...")

    if Process.alive?(state) do
      Process.unlink(state)
      Process.exit(state, :kill)
    end

    state = Hallofmirrors.WatchTask.start_stream()
    {:noreply, state}
  end

  def restart(pid) do
    Logger.debug("Throwing restart...")
    GenServer.cast(pid, {:restart})
  end
end
