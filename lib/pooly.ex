defmodule Pooly do
  @moduledoc """
  Pooly from The Little Elixir & OTP Guidebook
  """

  def start(_type, _args) do
    pool_config = [mfa: {Pooly.SampleWorker, :start_link, []}, size: 5]
    start_pool(pool_config)
  end

  def start_pool(pool_config) do
    Pooly.Supervisor.start_link(pool_config)
  end

  def checkout do
  end

  def checkin(worker_pid) do
  end

  def status do
  end
end
