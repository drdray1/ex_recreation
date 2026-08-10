defmodule ExRecreation.Client do
  @moduledoc """
  Holds the connection settings for the recreation.gov API — the base URL, the
  `User-Agent` to send, and an optional `Req.Test` plug for tests.

  Build one with `ExRecreation.new/1` and pass it to every resource call:

      client = ExRecreation.new()
      ExRecreation.month(client, "251864", ~D[2026-11-01])

  ## No credentials

  There are none. The endpoints this library talks to are the same ones
  recreation.gov's own web front-end calls, and they are served unauthenticated
  — no API key, no session, not even a `User-Agent` is required.

  Recreation.gov *does* publish an official key'd API (RIDB, at
  `ridb.recreation.gov`), but it only serves static metadata — facilities,
  descriptions, coordinates. It has no live availability, which is the whole
  point of this library, so it is not used here.
  """

  @default_base_url "https://www.recreation.gov/api"

  # Sent so we identify as a normal browser client rather than an anonymous
  # script. Nothing here is required by the API — it is politeness, not evasion.
  @default_user_agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " <>
                        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36"

  @type t :: %__MODULE__{
          base_url: String.t(),
          user_agent: String.t(),
          plug: term() | nil
        }

  defstruct base_url: @default_base_url,
            user_agent: @default_user_agent,
            plug: nil

  @doc """
  Builds a client.

  Options:

    * `:base_url` — override the API base URL (defaults to
      `#{@default_base_url}`).
    * `:user_agent` — override the `User-Agent` header for this client only.
    * `:plug` — a `Req.Test` stub (e.g. `{Req.Test, MyStub}`) used to intercept
      requests in tests.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      user_agent: Keyword.get(opts, :user_agent, user_agent()),
      plug: Keyword.get(opts, :plug)
    }
  end

  @doc "The default User-Agent (overridable via `config :ex_recreation, :user_agent`)."
  @spec user_agent() :: String.t()
  def user_agent, do: Application.get_env(:ex_recreation, :user_agent, @default_user_agent)
end
