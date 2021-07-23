defmodule MojitoTest do
  use ExSpec, async: true
  doctest Mojito
  doctest Mojito.Utils

  alias Mojito.{Error, Headers}

  context "url validation" do
    it "fails on url without protocol" do
      assert({:error, _} = Mojito.request(:get, "localhost/path"))
      assert({:error, _} = Mojito.request(:get, "/localhost/path"))
      assert({:error, _} = Mojito.request(:get, "//localhost/path"))
      assert({:error, _} = Mojito.request(:get, "localhost//path"))
    end

    it "fails on url with bad protocol" do
      assert({:error, _} = Mojito.request(:get, "garbage://localhost/path"))
      assert({:error, _} = Mojito.request(:get, "ftp://localhost/path"))
    end

    it "fails on url without hostname" do
      assert({:error, _} = Mojito.request(:get, "http://"))
    end

    it "fails on blank url" do
      assert({:error, err} = Mojito.request(:get, ""))
      assert(is_binary(err.message))
    end

    it "fails on nil url" do
      assert({:error, err} = Mojito.request(:get, nil))
      assert(is_binary(err.message))
    end
  end

  context "method validation" do
    it "fails on blank method" do
      assert({:error, err} = Mojito.request("", "https://cool.com"))
      assert(is_binary(err.message))
    end

    it "fails on nil method" do
      assert({:error, err} = Mojito.request(nil, "https://cool.com"))
      assert(is_binary(err.message))
    end
  end

  context "local server tests" do
    @http_port Application.get_env(:mojito, :test_server_http_port)
    @https_port Application.get_env(:mojito, :test_server_https_port)

    defp head(path, opts \\ []) do
      Mojito.head(
        "http://localhost:#{@http_port}#{path}",
        [],
        opts
      )
    end

    defp get(path, opts \\ []) do
      Mojito.get(
        "http://localhost:#{@http_port}#{path}",
        [],
        opts
      )
    end

    defp get_with_user(path, user, opts \\ []) do
      Mojito.get(
        "http://#{user}@localhost:#{@http_port}#{path}",
        [],
        opts
      )
    end

    defp get_with_user_and_pass(path, user, pass, opts \\ []) do
      Mojito.get(
        "http://#{user}:#{pass}@localhost:#{@http_port}#{path}",
        [],
        opts
      )
    end

    defp post(path, body_obj, opts \\ []) do
      body = Jason.encode!(body_obj)
      headers = [{"content-type", "application/json"}]

      Mojito.post(
        "http://localhost:#{@http_port}#{path}",
        headers,
        body,
        opts
      )
    end

    defp put(path, body_obj, opts \\ []) do
      body = Jason.encode!(body_obj)
      headers = [{"content-type", "application/json"}]

      Mojito.put(
        "http://localhost:#{@http_port}#{path}",
        headers,
        body,
        opts
      )
    end

    defp patch(path, body_obj, opts \\ []) do
      body = Jason.encode!(body_obj)
      headers = [{"content-type", "application/json"}]

      Mojito.patch(
        "http://localhost:#{@http_port}#{path}",
        headers,
        body,
        opts
      )
    end

    defp delete(path, opts \\ []) do
      Mojito.delete(
        "http://localhost:#{@http_port}#{path}",
        [],
        opts
      )
    end

    defp options(path, opts \\ []) do
      Mojito.options(
        "http://localhost:#{@http_port}#{path}",
        [],
        opts
      )
    end

    defp get_ssl(path, opts \\ []) do
      Mojito.get(
        "https://localhost:#{@https_port}#{path}",
        [],
        [transport_opts: [verify: :verify_none]] ++ opts
      )
    end

    it "accepts kwlist input" do
      assert(
        {:ok, _response} =
          Mojito.request(method: :get, url: "http://localhost:#{@http_port}/")
      )
    end

    it "accepts pool: true" do
      assert(
        {:ok, _response} =
          Mojito.request(
            method: :get,
            url: "http://localhost:#{@http_port}/",
            opts: [pool: true]
          )
      )
    end

    it "accepts pool: false" do
      assert(
        {:ok, _response} =
          Mojito.request(
            method: :get,
            url: "http://localhost:#{@http_port}/",
            opts: [pool: false]
          )
      )
    end

    it "accepts pool: pid" do
      child_spec = Mojito.Pool.Poolboy.Single.child_spec()
      {:ok, pool_pid} = Supervisor.start_child(Mojito.Supervisor, child_spec)

      assert(
        {:ok, _response} =
          Mojito.request(
            method: :get,
            url: "http://localhost:#{@http_port}/",
            opts: [pool: pool_pid]
          )
      )
    end

    it "can make HTTP requests" do
      assert({:ok, response} = get("/"))
      assert(200 == response.status_code)
      assert("Hello world!" == response.body)
      assert(12 == response.size)
      assert("12" == Headers.get(response.headers, "content-length"))
    end

    it "can use HTTP/1.1" do
      assert({:ok, response} = get("/", protocols: [:http1]))
      assert(200 == response.status_code)
      assert("Hello world!" == response.body)
      assert(12 == response.size)
      assert("12" == Headers.get(response.headers, "content-length"))
    end

    it "can use HTTP/2" do
      assert({:ok, response} = get("/", protocols: [:http2]))
      assert(200 == response.status_code)
      assert("Hello world!" == response.body)
      assert(12 == response.size)
      assert("12" == Headers.get(response.headers, "content-length"))
    end

    it "can make HTTPS requests" do
      assert({:ok, response} = get_ssl("/"))
      assert(200 == response.status_code)
      assert("Hello world!" == response.body)
      assert(12 == response.size)
      assert("12" == Headers.get(response.headers, "content-length"))
    end

    it "handles timeouts" do
      assert({:ok, _} = get("/", timeout: 100))
      assert({:error, %Error{reason: :timeout}} = get("/wait1", timeout: 100))
    end

    it "handles timeouts even on long requests" do
      port = Application.get_env(:mojito, :test_server_http_port)
      {:ok, conn} = Mojito.Conn.connect("http://localhost:#{port}")

      mint_conn =
        Map.put(conn.conn, :request, %{
          ref: nil,
          state: :status,
          method: :get,
          version: nil,
          status: nil,
          headers_buffer: [],
          content_length: nil,
          connection: [],
          transfer_encoding: [],
          body: nil
        })

      conn = %{conn | conn: mint_conn}

      pid = self()

      spawn(fn ->
        socket = conn.conn.socket
        Process.sleep(30)
        send(pid, {:tcp, socket, "HTTP/1.1 200 OK\r\nserver: Cowboy"})
        Process.sleep(30)
        send(pid, {:tcp, socket, "\r\ndate: Thu, 25 Apr 2019 10:48:25"})
        Process.sleep(30)
        send(pid, {:tcp, socket, " GMT\r\ncontent-length: 12\r\ncache-"})
        Process.sleep(30)
        send(pid, {:tcp, socket, "control: max-age=0, private, must-"})
        Process.sleep(30)
        send(pid, {:tcp, socket, "revalidate\r\n\r\nHello world!"})
      end)

      assert(
        {:error, %{reason: :timeout}} =
          Mojito.Request.Single.receive_response(
            conn,
            %Mojito.Response{},
            100
          )
      )
    end

    it "can set a max size" do
      assert(
        {:error, %Mojito.Error{message: nil, reason: :max_body_size_exceeded}} ==
          get("/infinite", timeout: 10000, max_body_size: 10)
      )
    end

    it "handles requests after a timeout when pooling" do
      child_spec = Mojito.Pool.Poolboy.Single.child_spec(size: 1)
      {:ok, pool_pid} = Supervisor.start_child(Mojito.Supervisor, child_spec)

      assert(
        {:error, %{reason: :timeout}} =
          get("/wait?d=500", timeout: 1, pool: pool_pid)
      )

      Process.sleep(100)

      assert(
        {:ok, %{body: "Hello Alice!"}} =
          get("?name=Alice", pool: pool_pid, timeout: 5000)
      )
    end

    it "handles requests after a timeout" do
      assert({:error, %{reason: :timeout}} = get("/wait?d=10", timeout: 1))
      Process.sleep(100)
      assert({:ok, %{body: "Hello Alice!"}} = get("?name=Alice"))
    end

    it "handles URL query params" do
      assert({:ok, %{body: "Hello Alice!"}} = get("/?name=Alice"))
      assert({:ok, %{body: "Hello Alice!"}} = get("?name=Alice"))
    end

    it "can post data" do
      assert({:ok, response} = post("/post", %{name: "Charlie"}))
      resp_body = response.body |> Jason.decode!()
      assert("Charlie" == resp_body["name"])
    end

    it "handles user+pass in URL" do
      assert({:ok, %{status_code: 500}} = get("/auth"))

      assert(
        {:ok, %{status_code: 200} = response} = get_with_user("/auth", "hi")
      )

      assert(%{"user" => "hi", "pass" => nil} = Jason.decode!(response.body))

      assert(
        {:ok, %{status_code: 200} = response} =
          get_with_user_and_pass("/auth", "hi", "mom")
      )

      assert(%{"user" => "hi", "pass" => "mom"} = Jason.decode!(response.body))
    end

    it "can make HEAD request" do
      assert({:ok, response} = head("/"))
      assert(200 == response.status_code)
      assert("" == response.body)
      assert("12" == Headers.get(response.headers, "content-length"))
    end

    it "can make PATCH request" do
      assert({:ok, response} = patch("/patch", %{name: "Charlie"}))
      resp_body = response.body |> Jason.decode!()
      assert("Charlie" == resp_body["name"])
    end

    it "can make PUT request" do
      assert({:ok, response} = put("/put", %{name: "Charlie"}))
      resp_body = response.body |> Jason.decode!()
      assert("Charlie" == resp_body["name"])
    end

    it "can make DELETE request" do
      assert({:ok, response} = delete("/delete"))
      assert(200 == response.status_code)
    end

    it "can make OPTIONS request" do
      assert({:ok, response} = options("/"))

      assert(
        "OPTIONS, GET, HEAD, POST, PATCH, PUT, DELETE" ==
          Headers.get(response.headers, "allow")
      )
    end

    it "expands gzip" do
      assert({:ok, response} = get("/gzip"))
      assert("{\"ok\":true}\n" == response.body)

      assert({:ok, response} = get("/gzip", raw: true))
      assert("{\"ok\":true}\n" != response.body)
    end

    it "expands deflate" do
      assert({:ok, response} = get("/deflate"))
      assert("{\"ok\":true}\n" == response.body)

      assert({:ok, response} = get("/deflate", raw: true))
      assert("{\"ok\":true}\n" != response.body)
    end

    it "handles connection:close response" do
      assert({:ok, response} = get("/close", pool: false))
      assert("close" == response.body)
    end

    it "handles ssl connection:close response" do
      assert({:ok, response} = get_ssl("/close", pool: false))
      assert("close" == response.body)
    end

    it "can POST big bodies over HTTP/1" do
      big = String.duplicate("x", 5_000_000)
      body = %{name: big}
      assert({:ok, response} = post("/post", body, protocols: [:http1]))
      assert({:ok, map} = Jason.decode(response.body))
      assert(%{"name" => big} == map)
    end

    it "can POST big bodies over HTTP/2" do
      big = String.duplicate("é", 2_500_000)
      body = %{name: big}
      assert({:ok, response} = post("/post", body, protocols: [:http2]))
      assert({:ok, map} = Jason.decode(response.body))
      assert(%{"name" => big} == map)
    end

    it "handles response chunks arriving during stream_request_body" do
      ## sending a body this big will trigger a 500 error in Cowboy
      ## because we have not configured it otherwise
      big = String.duplicate("x", 100_000_000)
      body = %{name: big}

      assert(
        {:ok, response} =
          post("/post", body, protocols: [:http2], timeout: 10_000)
      )

      assert(500 == response.status_code)
    end

    it "handles timeouts during stream_request_body" do
      big = String.duplicate("x", 5_000_000)
      body = %{name: big}

      assert(
        {:error, %{reason: :timeout}} =
          post("/post", body, protocols: [:http2], timeout: 10)
      )
    end
  end

  context "external tests" do
    it "can make HTTPS requests using proper cert chain by default" do
      assert({:ok, _} = Mojito.request(:get, "https://github.com"))
    end
  end
end
