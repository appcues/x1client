defmodule X1Client.Conn do
  @moduledoc ~S"""
  `X1Client.Conn` provides a lower-level API than `X1Client`, yet
  still higher-level than XHTTP.  It is intended for usage where the
  `X1Client` interface is too simple, e.g. for connection pooling.
  """

  alias X1Client.Response

  @opaque t :: XHTTP1.Conn.t()

  @doc ~S"""
  Connects to the server specified in the given URL,
  returning a connection to the server.  No requests are made.
  """
  @spec connect(String.t()) :: {:ok, t} | {:error, any}
  def connect(url) do
    with {:ok, protocol, hostname, port} <- decompose_url(url),
         {:ok, transport} <- protocol_to_transport(protocol) do
      XHTTP1.Conn.connect(hostname, port, transport: transport)
    end
  end

  @doc ~S"""
  Initiates a request on the given connection.
  """
  @spec request(t, atom, String.t(), [{String.t(), String.t()}], String.t(), Keyword.t()) ::
          {:ok, t, reference} | {:error, any}
  def request(conn, method, url, headers, payload, _opts \\ []) do
    with {:ok, relative_url} <- make_relative_url(url) do
      XHTTP1.Conn.request(conn, method, relative_url, headers, payload)
    end
  end

  @doc ~S"""
  Handles the streaming of the response body in
  TCP/SSL active mode, stopping when the response is complete (generally
  when we've received as much data as the Content-length response header
  claimed).

  These messages are received in the caller process, so take care to
  execute this in a process where there are no other message-senders.
  """
  @spec stream_response(t, Keyword.t()) :: {:ok, t, %Response{}} | {:error, any}

  def stream_response(conn, opts \\ []), do: stream_response(conn, %Response{}, opts)

  @request_timeout Application.get_env(:x1client, :request_timeout, 5000)

  @spec stream_response(t, %Response{}, Keyword.t()) :: {:ok, t, %Response{}} | {:error, any}

  defp stream_response(conn, %{done: true} = response, _opts), do: {:ok, conn, response}

  defp stream_response(conn, response, opts) do
    timeout = opts[:timeout] || @request_timeout

    receive do
      tcp_message ->
        case XHTTP1.Conn.stream(conn, tcp_message) do
          {:ok, conn, resps} ->
            stream_response(conn, build_response(response, resps), opts)

          other ->
            other
        end
    after
      timeout -> {:error, :timeout}
    end
  end

  ## `build_response/2` adds streamed response chunks from XHTTP1 into
  ## an `%X1Client.Response{}` map.

  @typep response_chunk ::
           {:status, reference, non_neg_integer}
           | {:headers, reference, [{String.t(), String.t()}]}
           | {:data, reference, String.t()}
           | {:done, reference}

  @spec build_response(%Response{}, [response_chunk]) :: %Response{}

  defp build_response(response, []), do: response

  defp build_response(response, [chunk | rest]) do
    response =
      case chunk do
        {:status, _request_ref, status} ->
          %{response | status_code: status}

        {:headers, _request_ref, headers} ->
          # TODO clean up header format into map
          %{response | headers: headers}

        {:data, _request_ref, chunk} ->
          %{response | body: [response.body | [chunk]]}

        {:done, _request_ref} ->
          body = :erlang.list_to_binary(response.body)
          %{response | done: true, body: body}
      end

    build_response(response, rest)
  end

  ## `decompose_url/1` extracts the protocol, host, and port from a web URL.

  defp decompose_url(url) do
    fu = Fuzzyurl.from_string(url)

    port =
      cond do
        fu.port -> String.to_integer(fu.port)
        fu.protocol == "http" -> 80
        fu.protocol == "https" -> 443
        :else -> nil
      end

    cond do
      !fu.protocol -> {:error, "protocol missing from url"}
      !fu.hostname -> {:error, "hostname missing from url"}
      !port -> {:error, "could not determine port for url"}
      :else -> {:ok, fu.protocol, fu.hostname, port}
    end
  end

  ## `make_relative_url/1` strips the protocol, hostname, and port from
  ## a web URL, returning the path (starting with a slash).

  defp make_relative_url("http://" <> rest), do: {:ok, get_path(rest)}

  defp make_relative_url("https://" <> rest), do: {:ok, get_path(rest)}

  defp make_relative_url(url), do: {:error, "could not make url relative: #{url}"}

  defp get_path(url_part) do
    "/" <>
      case String.split(url_part, "/", parts: 2) do
        [_hostname, path] -> path
        _ -> ""
      end
  end

  defp protocol_to_transport("http"), do: {:ok, :gen_tcp}

  defp protocol_to_transport("https"), do: {:ok, :ssl}

  defp protocol_to_transport(other), do: {:error, "protocol not recognized: #{other}"}
end
