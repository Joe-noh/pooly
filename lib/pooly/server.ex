defmodule Pooly.Server do
  use GenServer
  import Supervisor.Spec

  defmodule State do
    defstruct sup: nil, worker_sup: nil, size: nil, workers: nil, mfa: nil
  end

  # API

  def start_link(sup, pool_config) do
    GenServer.start_link(__MODULE__, [sup, pool_config], name: __MODULE__)
  end

  # Callbacks

  def init([sup, pool_config]) when is_pid(sup) do
    init(pool_config, %State{sup: sup})
  end
  def init([{:mfa, mfa} | rest], state) do
    init(rest, %{state | mfa: mfa})
  end
  def init([{:size, size} | rest], state) do
    init(rest, %{state | size: size})
  end
  def init([_ | rest], state) do
    init(rest, state)
  end
  def init([], state) do
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  def handle_info(:start_worker_supervisor, state = %{sup: sup, mfa: mfa, size: size}) do
    {:ok, worker_sup} = Supervisor.start_child(sup, supervisor_spec(mfa))
    workers = prepopulate(size, worker_sup)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  defp supervisor_spec(mfa) do
    supervisor(Pooly.WorkerSupervisor, [mfa], [restart: :temporary])
  end

  defp prepopulate(size, worker_sup) do
    prepopulate(size, worker_sup, [])
  end
  defp prepopulate(size, _sup, workers) when size < 1 do
    workers
  end
  defp prepopulate(size, sup, workers) do
    {:ok, worker} = Supervisor.start_child(sup, [[]])
    prepopulate(size - 1, sup, [worker | workers])
  end
end
