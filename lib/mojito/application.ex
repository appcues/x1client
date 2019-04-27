defmodule Mojito.Application do
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      Mojito.Pool.Manager,
      {Registry,
       keys: :unique,
       name: Mojito.Pool.Registry,
       partitions: System.schedulers_online()},
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mojito.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
