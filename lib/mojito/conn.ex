defmodule Mojito.Conn do
  @moduledoc false

  alias Mojito.{Error, Telemetry, Utils}

  defstruct conn: nil,
            protocol: nil,
            hostname: nil,
            port: nil

  @type t :: %Mojito.Conn{}

  @doc ~S"""
  Connects to the specified endpoint, returning a connection to the server.
  No requests are made.
  """
  @spec connect(String.t(), Keyword.t()) :: {:ok, t} | {:error, any}
  def connect(url, opts \\ []) do
    with {:ok, protocol, hostname, port} <- Utils.decompose_url(url) do
      connect(protocol, hostname, port, opts)
    end
  end

  @doc ~S"""
  Closes a connection
  """
  @spec close(t) :: :ok
  def close(conn) do
    Mint.HTTP.close(conn.conn)
    :ok
  end

  @doc ~S"""
  Connects to the server specified in the given URL,
  returning a connection to the server.  No requests are made.
  """
  @spec connect(String.t(), String.t(), non_neg_integer, Keyword.t()) ::
          {:ok, t} | {:error, any}
  def connect(protocol, hostname, port, opts \\ []) do
    with meta <- %{host: hostname, port: port},
         start_time <- Telemetry.start(:connect, meta),
         {:ok, proto} <- protocol_to_atom(protocol),
         {:ok, mint_conn} <- Mint.HTTP.connect(proto, hostname, port, opts) do
      Telemetry.stop(:connect, start_time, meta)

      {:ok,
       %Mojito.Conn{
         conn: mint_conn,
         protocol: proto,
         hostname: hostname,
         port: port
       }}
    end
  end

  defp protocol_to_atom("http"), do: {:ok, :http}
  defp protocol_to_atom("https"), do: {:ok, :https}
  defp protocol_to_atom(:http), do: {:ok, :http}
  defp protocol_to_atom(:https), do: {:ok, :https}

  defp protocol_to_atom(proto),
    do: {:error, %Error{message: "bad protocol #{inspect(proto)}"}}

  @doc ~S"""
  Return true if the connection is http/1.1
  """
  def is_http11(conn) do
    case conn.conn do
      %Mint.HTTP1{} -> true
      _ -> false
    end
  end

  @doc ~S"""
  Initiates a request on the given connection.  Returns the updated Conn and
  a reference to this request (which is required when receiving pipelined
  responses).
  """
  @spec request(t, Mojito.request()) :: {:ok, t, reference} | {:error, any}
  def request(conn, request) do
    max_body_size = request.opts[:max_body_size]
    response = %Mojito.Response{body: [], size: max_body_size}

    with {:ok, relative_url, auth_headers} <-
           Utils.get_relative_url_and_auth_headers(request.url),
         {:ok, mint_conn, request_ref} <-
           Mint.HTTP.request(
             conn.conn,
             method_to_string(request.method),
             relative_url,
             auth_headers ++ request.headers,
             :stream
           ),
         {:ok, mint_conn, response} <-
           stream_request_body(mint_conn, request_ref, response, request.body) do
      {:ok, %{conn | conn: mint_conn}, request_ref, response}
    end
  end

  defp stream_request_body(mint_conn, request_ref, response, nil) do
    stream_request_body(mint_conn, request_ref, response, "")
  end

  defp stream_request_body(mint_conn, request_ref, response, "") do
    with {:ok, mint_conn} <-
           Mint.HTTP.stream_request_body(mint_conn, request_ref, :eof) do
      {:ok, mint_conn, response}
    end
  end

  defp stream_request_body(
         %Mint.HTTP1{} = mint_conn,
         request_ref,
         response,
         body
       ) do
    {chunk, rest} = split_chunk(body, 65_535)

    with {:ok, mint_conn} <-
           Mint.HTTP.stream_request_body(mint_conn, request_ref, chunk) do
      stream_request_body(mint_conn, request_ref, response, rest)
    end
  end

  defp stream_request_body(
         %Mint.HTTP2{} = mint_conn,
         request_ref,
         response,
         body
       ) do
    chunk_size =
      min(
        Mint.HTTP2.get_window_size(mint_conn, {:request, request_ref}),
        Mint.HTTP2.get_window_size(mint_conn, :connection)
      )

    {chunk, rest} = split_chunk(body, chunk_size)

    with {:ok, mint_conn} <-
           Mint.HTTP.stream_request_body(mint_conn, request_ref, chunk) do
      {mint_conn, response} =
        if is_nil(rest) do
          {mint_conn, response}
        else
          {:ok, mint_conn, resps} =
            receive do
              msg -> Mint.HTTP.stream(mint_conn, msg)
            end

          {:ok, response} = Mojito.Response.apply_resps(response, resps)

          {mint_conn, response}
        end

      if response.complete do
        {:ok, mint_conn, response}
      else
        stream_request_body(mint_conn, request_ref, response, rest)
      end
    end
  end

  defp method_to_string(m) when is_atom(m) do
    m |> to_string |> String.upcase()
  end

  defp method_to_string(m) when is_binary(m) do
    m |> String.upcase()
  end

  defp split_chunk(binary, chunk_size)
       when is_binary(binary) and is_integer(chunk_size) do
    case binary do
      <<chunk::binary-size(chunk_size), rest::binary>> ->
        {chunk, rest}

      _ ->
        {binary, nil}
    end
  end
end
