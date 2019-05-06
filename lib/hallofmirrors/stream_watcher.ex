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
    {:ok, pid} = supervise_stream()
    {:ok, pid}
  end

  defp supervise_stream do
    [
      Supervisor.child_spec({Hallofmirrors.WatchTask, [:start_stream]}, id: :twitter),
      Supervisor.child_spec({Hallofmirrors.WatchTask, [:subreddit_loop]}, id: :reddit)
    ]
    |> Supervisor.start_link(strategy: :one_for_one)
  end

  def handle_cast({:restart}, state) do
    Logger.debug("Restarting stream...")

    if Process.alive?(state) do
      Process.unlink(state)
      Process.exit(state, :kill)
    end

    {:ok, pid} = supervise_stream()
    {:noreply, pid}
  end

  def restart(pid) do
    Logger.debug("Throwing restart...")
    GenServer.cast(pid, {:restart})
  end
end
