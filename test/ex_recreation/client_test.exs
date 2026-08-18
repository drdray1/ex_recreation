defmodule ExRecreation.ClientTest do
  use ExUnit.Case, async: false

  alias ExRecreation.Client

  describe "new/1" do
    test "defaults to the public recreation.gov api with a browser user-agent" do
      client = Client.new()

      assert client.base_url == "https://www.recreation.gov/api"
      assert client.user_agent =~ "Mozilla/5.0"
      assert client.plug == nil
    end

    test "accepts base_url, user_agent and plug overrides" do
      client =
        Client.new(base_url: "http://localhost:4000/api", user_agent: "x", plug: :some_plug)

      assert client.base_url == "http://localhost:4000/api"
      assert client.user_agent == "x"
      assert client.plug == :some_plug
    end

    test "carries no session by default" do
      client = Client.new()

      assert client.cookies == %{}
      assert client.access_token == nil
      refute Client.authenticated?(client)
    end

    test "accepts a session up front" do
      client = Client.new(cookies: %{"sid" => "abc"}, access_token: "jwt")

      assert client.cookies == %{"sid" => "abc"}
      assert client.access_token == "jwt"
      assert Client.authenticated?(client)
    end
  end

  describe "authenticate/2" do
    test "attaches cookies and a token to an existing client" do
      client =
        Client.new() |> Client.authenticate(cookies: %{"sid" => "abc"}, access_token: "jwt")

      assert client.cookies == %{"sid" => "abc"}
      assert client.access_token == "jwt"
      assert Client.authenticated?(client)
    end

    test "leaves untouched what it is not given, so a token can be refreshed alone" do
      client =
        Client.new(cookies: %{"sid" => "abc"}, access_token: "old")
        |> Client.authenticate(access_token: "new")

      assert client.cookies == %{"sid" => "abc"}
      assert client.access_token == "new"
    end

    test "preserves the rest of the client" do
      client =
        Client.new(base_url: "http://localhost:4000/api", user_agent: "x", plug: :some_plug)
        |> Client.authenticate(cookies: %{"sid" => "abc"})

      assert client.base_url == "http://localhost:4000/api"
      assert client.user_agent == "x"
      assert client.plug == :some_plug
    end

    test "clears a session when handed an empty one" do
      client =
        Client.new(cookies: %{"sid" => "abc"}, access_token: "jwt")
        |> Client.authenticate(cookies: %{}, access_token: nil)

      refute Client.authenticated?(client)
    end

    test "a token alone, or a cookie alone, counts as authenticated" do
      assert Client.authenticated?(Client.new(access_token: "jwt"))
      assert Client.authenticated?(Client.new(cookies: %{"sid" => "abc"}))
    end

    # async: false — this test mutates application env.
    test "picks up a globally configured user agent" do
      Application.put_env(:ex_recreation, :user_agent, "configured-agent/1.0")
      on_exit(fn -> Application.delete_env(:ex_recreation, :user_agent) end)

      assert Client.user_agent() == "configured-agent/1.0"
      assert Client.new().user_agent == "configured-agent/1.0"
    end

    test "an explicit user_agent still beats the configured one" do
      Application.put_env(:ex_recreation, :user_agent, "configured-agent/1.0")
      on_exit(fn -> Application.delete_env(:ex_recreation, :user_agent) end)

      assert Client.new(user_agent: "explicit/2.0").user_agent == "explicit/2.0"
    end
  end
end
