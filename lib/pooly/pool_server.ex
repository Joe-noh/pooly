defmodule Pooly.PoolServer do
  use GenServer
  import Supervisor.Spec

  defmodule State do
    defstruct [
      pool_sup: nil,
      worker_sup: nil,
      monitors: nil,
      size: nil,
      workers: nil,
      name: nil,
      mfa: nil,
    ]
  end

  def start_link(pool_sup, pool_config) do
    GenServer.start_link(__MODULE__, [pool_sup, pool_config], name: name(pool_config[:name]))
  end

  def checkout(pool_name) do
    GenServer.call(name(pool_name), :checkout)
  end

  def checkin(pool_name, worker_pid) do
    GenServer.cast(name(pool_name), {:checkin, worker_pid})
  end

  def status(pool_name) do
    GenServer.call(name(pool_name), :status)
  end

  # Callbacks

  def init([pool_sup, pool_config]) when is_pid(pool_sup) do
    Process.flag(:trap_exit, true)
    monitors = :ets.new(:monitors, [:private])

    init(pool_config, %State{pool_sup: pool_sup, monitors: monitors})
  end

  def init([{:name, name} | rest], state) do
    init(rest, %State{state | name: name})
  end
  def init([{:mfa, mfa} | rest], state) do
    init(rest, %State{state | mfa: mfa})
  end
  def init([{:size, size} | rest], state) do
    init(rest, %State{state | size: size})
  end
  def init([_ | rest], state) do
    init(rest, state)
  end
  def init([], state) do
    send(self(), :start_worker_supervisor)
    {:ok, state}
  end

  def handle_call(:checkout, _from, state = %{workers: []}) do
    {:reply, :noproc, state}
  end
  def handle_call(:checkout, {from_pid, _ref}, state = %{workers: [worker | rest], monitors: monitors}) do
    :ets.insert(monitors, {worker, Process.monitor(from_pid)})

    {:reply, worker, %{state | workers: rest}}
  end

  def handle_call(:status, _from, state = %{workers: workers, monitors: monitors}) do
    {:reply, {length(workers), :ets.info(monitors, :size)}, state}
  end


  def handle_cast({:checkin, worker}, state = %{workers: workers, monitors: monitors}) do
    case :ets.lookup(monitors, worker) do
      [{pid, ref}] ->
        Process.demonitor(ref)
        :ets.delete(monitors, pid)

        {:noreply, %{state | workers: [pid | workers]}}
      [] ->
        {:noreply, state}
    end
  end

  def handle_info(:start_worker_supervisor, state = %{pool_sup: pool_sup, mfa: mfa, size: size, name: name}) do
    {:ok, worker_sup} = Supervisor.start_child(pool_sup, supervisor_spec(name, mfa))
    workers = prepopulate(size, worker_sup)

    {:noreply, %{state | worker_sup: worker_sup, workers: workers}}
  end

  def handle_info({:DOWN, ref, _, _, _}, state = %{workers: workers, monitors: monitors}) do
    case :ets.match(monitors, {:"$1", ref}) do
      [[pid]] ->
        :ets.delete(monitors, pid)
        new_state = %{state | workers: [pid | workers]}
        {:noreply, new_state}
      [[]] ->
        {:noreply, state}
    end
  end

  def handle_info({:EXIT, pid, _reason}, state = %{workers: workers, monitors: monitors, pool_sup: pool_sup}) do
    case :ets.lookup(monitors, pid) do
      [{pid, ref}] ->
        Process.demonitor(ref)
        :ets.delete(monitors, pid)
        new_state = %{state | workers: [new_worker(pool_sup) | workers]}
        {:noreply, new_state}
      [] ->
        {:noreply, state}
    end
  end

  def terminate(_reason, _state) do
    :ok
  end

  defp name(pool_name) do
    :"#{pool_name}Server"
  end

  defp supervisor_spec(name, mfa) do
    opts = [id: name <> "WorkerSupervisor", restart: :temporary]
    supervisor(Pooly.WorkerSupervisor, [self(), mfa], opts)
  end

  defp prepopulate(size, sup) do
    prepopulate(size, sup, [])
  end
  defp prepopulate(size, _sup, workers) when size < 1 do
    workers
  end
  defp prepopulate(size, sup, workers) do
    prepopulate(size - 1, sup, [new_worker(sup) | workers])
  end
  defp new_worker(sup) do
    {:ok, worker} = Supervisor.start_child(sup, [[]])
    worker
  end
end
