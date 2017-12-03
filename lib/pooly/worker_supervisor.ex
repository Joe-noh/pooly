defmodule Pooly.WorkerSupervisor do
  use Supervisor

  # API

  def start_link(mfa = {_, _, _}) do
    Supervisor.start_link(__MODULE__, mfa)
  end

  # Callbacks

  def init({m, f, a}) do
    children = [
      worker(m, a, [restart: :permanent, function: f])
    ]
    opts = [
      strategy: :simple_one_for_one,
      max_restarts: 5,
      max_seconds: 5,
    ]

    supervise(children, opts)
  end
end
