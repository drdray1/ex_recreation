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
