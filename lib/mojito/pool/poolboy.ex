defmodule Mojito.Pool.Poolboy do
  @moduledoc false

  ## Mojito.Pool.Poolboy is an HTTP client with high-performance, easy-to-use
  ## connection pools based on the Poolboy library.
  ##
  ## Pools are maintained automatically by Mojito, requests are matched to
  ## the correct pool without user intervention, and multiple pools can be
  ## used for the same destination in order to reduce concurrency bottlenecks.
  ##
  ## Config parameters are explained in the `Mojito` moduledocs.

  @behaviour Mojito.Pool

  alias Mojito.{Config, Request, Utils}
  require Logger

  @doc ~S"""
  Performs an HTTP request using a connection pool, creating that pool if
  it didn't already exist.  Requests are always matched to a pool that is
  connected to the correct destination host and port.
  """
  @impl true
  def request(%{} = request) do
    with {:ok, valid_request} <- Request.validate_request(request),
         {:ok, _proto, host, port} <- Utils.decompose_url(valid_request.url),
         pool_key <- pool_key(host, port),
         {:ok, pool} <- get_pool(pool_key) do
      do_request(pool, pool_key, valid_request)
    end
  end

  defp do_request(pool, pool_key, request) do
    case Mojito.Pool.Poolboy.Single.request(pool, request) do
      {:error, %{reason: :checkout_timeout}} ->
        case start_pool(pool_key) do
          {:ok, pid} ->
            Mojito.Pool.Poolboy.Single.request(pid, request)
          error ->
            error
        end
      other ->
        other
    end
  end

  ## Returns a pool for the given destination, starting one or more
  ## if necessary.
  @doc false
  @spec get_pool(any) :: {:ok, pid} | {:error, Mojito.error()}
  def get_pool(pool_key) do
    case get_pools(pool_key) do
      [] ->
        opts = Mojito.Pool.pool_opts(pool_key)
        1..opts[:pools] |> Enum.each(fn _ -> start_pool(pool_key) end)
        get_pool(pool_key)

      pools ->
        {:ok, Enum.random(pools)}
    end
  end

  ## Returns all pools for the given destination.
  @doc false
  @spec get_pools(any) :: [pid]
  defp get_pools(pool_key) do
    Mojito.Pool.Poolboy.Registry
    |> Registry.lookup(pool_key)
    |> Enum.map(fn {_, pid} -> pid end)
  end

  ## Starts a new pool for the given destination.
  @doc false
  @spec start_pool(any) :: {:ok, pid} | {:error, Mojito.error()}
  def start_pool(pool_key) do
    old_trap_exit = Process.flag(:trap_exit, true)

    try do
      GenServer.call(
        Mojito.Pool.Poolboy.Manager,
        {:start_pool, pool_key},
        Config.timeout()
      )
    rescue
      e -> {:error, e}
    catch
      :exit, _ -> {:error, :checkout_timeout}
    after
      Process.flag(:trap_exit, old_trap_exit)
    end
    |> Utils.wrap_return_value()
  end

  ## Returns a key representing the given destination.
  @doc false
  @spec pool_key(String.t(), pos_integer) :: Mojito.Pool.pool_key()
  def pool_key(host, port) do
    {host, port}
  end
end
