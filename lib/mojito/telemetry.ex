defmodule Mojito.Telemetry do
  @moduledoc ~S"""
  Mojito's [Telemetry](https://github.com/beam-telemetry/telemetry)
  integration.

  All time measurements are emitted in `:millisecond` units by
  default. A different
  [Erlang time unit](https://erlang.org/doc/man/erlang.html#type-time_unit)
  can be chosen by setting a config parameter like so:

  ```
  config :mojito, Mojito.Telemetry, time_unit: :microsecond
  ```

  Mojito emits the following Telemetry events:

  * `[:mojito, :pool, :start]` before launching a pool
    - Measurements: `:system_time`
    - Metadata: `:host`, `:port`

  * `[:mojito, :pool, :stop]` after launching a pool
    - Measurements: `:system_time`, `:duration`
    - Metadata: `:host`, `:port`

  * `[:mojito, :connect, :start]` before connecting to a host
    - Measurements: `:system_time`
    - Metadata: `:host`, `:port`

  * `[:mojito, :connect, :stop]` after connecting to a host
    - Measurements: `:system_time`, `:duration`
    - Metadata: `:host`, `:port`

  * `[:mojito, :request, :start]` before making a request
    - Measurements: `:system_time`
    - Metadata: `:host`, `:port`, `:path`, `:method`

  * `[:mojito, :request, :stop]` after making a request
    - Measurements: `:system_time`, `:duration`
    - Metadata: `:host`, `:port`, `:path`, `:method`, `:status_code` (This value
        is otional. It includes the status code from a `Mojito.Response` struct)

  """

  @typep monotonic_time :: integer

  defp time_unit do
    Application.get_env(:mojito, Mojito.Telemetry)[:time_unit] || :millisecond
  end

  defp monotonic_time do
    :erlang.monotonic_time(time_unit())
  end

  defp system_time do
    :erlang.system_time(time_unit())
  end

  @doc false
  @spec start(atom, map) :: monotonic_time
  def start(name, meta \\ %{}) do
    start_time = monotonic_time()

    :telemetry.execute(
      [:mojito, name, :start],
      %{system_time: system_time()},
      meta
    )

    start_time
  end

  @doc false
  @spec stop(atom, monotonic_time, map) :: monotonic_time
  def stop(name, start_time, meta \\ %{}) do
    stop_time = monotonic_time()
    duration = stop_time - start_time

    :telemetry.execute(
      [:mojito, name, :stop],
      %{system_time: system_time(), duration: duration},
      meta
    )

    stop_time
  end
end
