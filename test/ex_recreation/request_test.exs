defmodule ExRecreation.RequestTest do
  use ExUnit.Case, async: true

  alias ExRecreation.{Fixtures, Request}

  @stub __MODULE__.Stub

  describe "request/4" do
    test "sends the user-agent and accept headers to the client's base url" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/thing"
        assert [user_agent] = Plug.Conn.get_req_header(conn, "user-agent")
        assert user_agent =~ "Mozilla/5.0"
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]

        Req.Test.json(conn, %{"payload" => %{"ok" => true}})
      end)

      assert {:ok, %{"ok" => true}} = Request.request(Fixtures.client(@stub), :get, "/thing")
    end

    test "passes query params through" do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string) == %{"a" => "1", "b" => "two"}
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      assert {:ok, %{}} =
               Request.request(Fixtures.client(@stub), :get, "/thing", params: [a: 1, b: "two"])
    end

    test "honours a per-client user-agent override" do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "user-agent") == ["aravaipa-watcher/1.0"]
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      client = ExRecreation.new(plug: {Req.Test, @stub}, user_agent: "aravaipa-watcher/1.0")
      assert {:ok, %{}} = Request.request(client, :get, "/thing")
    end

    test "sends no cookie or authorization header without a session" do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "cookie") == []
        assert Plug.Conn.get_req_header(conn, "authorization") == []
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      assert {:ok, %{}} = Request.request(Fixtures.client(@stub), :get, "/thing")
    end

    test "serializes a session's cookie jar into a single cookie header" do
      Req.Test.stub(@stub, fn conn ->
        assert [cookie] = Plug.Conn.get_req_header(conn, "cookie")
        assert cookie |> String.split("; ") |> Enum.sort() == ["other=2", "sid=abc"]
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      client =
        @stub
        |> Fixtures.client()
        |> ExRecreation.authenticate(cookies: %{"sid" => "abc", "other" => "2"})

      assert {:ok, %{}} = Request.request(client, :get, "/thing")
    end

    test "sends an access token as a bearer authorization header" do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer jwt-xyz"]
        assert Plug.Conn.get_req_header(conn, "cookie") == []
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      client = @stub |> Fixtures.client() |> ExRecreation.authenticate(access_token: "jwt-xyz")

      assert {:ok, %{}} = Request.request(client, :get, "/thing")
    end

    test "sends both when the session has both, alongside the usual headers" do
      Req.Test.stub(@stub, fn conn ->
        assert Plug.Conn.get_req_header(conn, "cookie") == ["sid=abc"]
        assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer jwt-xyz"]
        assert [user_agent] = Plug.Conn.get_req_header(conn, "user-agent")
        assert user_agent =~ "Mozilla/5.0"
        assert Plug.Conn.get_req_header(conn, "accept") == ["application/json"]
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      client =
        @stub
        |> Fixtures.client()
        |> ExRecreation.authenticate(cookies: %{"sid" => "abc"}, access_token: "jwt-xyz")

      assert {:ok, %{}} = Request.request(client, :get, "/thing")
    end

    test "sends a json body when given one" do
      Req.Test.stub(@stub, fn conn ->
        {:ok, body, _conn} = Plug.Conn.read_body(conn)
        assert Jason.decode!(body) == %{"hello" => "world"}
        Req.Test.json(conn, %{"payload" => %{}})
      end)

      assert {:ok, %{}} =
               Request.request(Fixtures.client(@stub), :post, "/thing", json: %{hello: "world"})
    end
  end

  describe "options/4" do
    test "a real client retries transient failures with exponential backoff" do
      options = Request.options(ExRecreation.new(), :get, "/thing")

      assert options[:retry] == :transient
      assert options[:max_retries] == 3
      refute Keyword.has_key?(options, :plug)

      # 500ms, 1s, 2s, 4s.
      assert Enum.map(0..3, options[:retry_delay]) == [500, 1000, 2000, 4000]
    end

    test "a client wired to a test plug disables retries so stubs return immediately" do
      options = Request.options(Fixtures.client(@stub), :get, "/thing")

      assert options[:retry] == false
      assert options[:plug] == {Req.Test, @stub}
      refute Keyword.has_key?(options, :max_retries)
    end

    test "omits json and params when they are not given" do
      options = Request.options(ExRecreation.new(), :get, "/thing")

      refute Keyword.has_key?(options, :json)
      refute Keyword.has_key?(options, :params)
    end

    test "carries method, base_url, path and headers" do
      client = ExRecreation.new(base_url: "https://example.test/api", user_agent: "ua/1")
      options = Request.options(client, :post, "/thing", params: [a: 1], json: %{b: 2})

      assert options[:method] == :post
      assert options[:base_url] == "https://example.test/api"
      assert options[:url] == "/thing"
      assert options[:params] == [a: 1]
      assert options[:json] == %{b: 2}
      assert {"user-agent", "ua/1"} in options[:headers]
    end
  end

  describe "handle_response/1" do
    test "unwraps the payload envelope" do
      response = {:ok, %Req.Response{status: 200, body: %{"payload" => %{"permit_id" => "1"}}}}
      assert {:ok, %{"permit_id" => "1"}} = Request.handle_response(response)
    end

    test "returns envelope-less bodies as-is, which is what /api/search does" do
      response = {:ok, %Req.Response{status: 200, body: %{"results" => []}}}
      assert {:ok, %{"results" => []}} = Request.handle_response(response)
    end

    test "maps error statuses to reason atoms" do
      for {status, reason} <- [
            {401, :unauthorized},
            {403, :forbidden},
            {404, :not_found},
            {429, :rate_limited}
          ] do
        assert {:error, ^reason} =
                 Request.handle_response({:ok, %Req.Response{status: status, body: ""}})
      end
    end

    test "falls back to :unexpected_status for other errors" do
      assert {:error, {:unexpected_status, 503}} =
               Request.handle_response({:ok, %Req.Response{status: 503, body: ""}})
    end

    test "wraps transport failures" do
      assert {:error, {:connection_error, :econnrefused}} =
               Request.handle_response({:error, :econnrefused})
    end
  end

  describe "query_params/2" do
    test "keeps allowed non-nil keys and drops everything else" do
      params = Request.query_params([size: 5, start: nil, bogus: "x"], [:size, :start])
      assert params == [size: 5]
    end

    test "returns an empty list when nothing matches" do
      assert Request.query_params([], [:size]) == []
    end
  end

  describe "transport errors" do
    test "surface through request/4" do
      Req.Test.stub(@stub, fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, {:connection_error, _}} =
               Request.request(Fixtures.client(@stub), :get, "/thing")
    end
  end
end
