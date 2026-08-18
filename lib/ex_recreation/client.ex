defmodule ExRecreation.Client do
  @moduledoc """
  Holds the connection settings for the recreation.gov API — the base URL, the
  `User-Agent` to send, an optional session, and an optional `Req.Test` plug for
  tests.

  Build one with `ExRecreation.new/1` and pass it to every resource call:

      client = ExRecreation.new()
      ExRecreation.month(client, "251864", ~D[2026-11-01])

  ## Credentials

  None are *required*. The endpoints this library talks to are the same ones
  recreation.gov's own web front-end calls, and they are served unauthenticated
  — no API key, no session, not even a `User-Agent`.

  A session may still be supplied. `authenticate/2` attaches cookies and a
  bearer token to a client, and every subsequent request carries them. This
  library does not establish such a session — it has no login flow and drives no
  browser. It only accepts one that a caller obtained elsewhere, which is what
  account-scoped reads need, and what lets a caller hand over a session
  established in a real browser if the plain endpoints ever start being
  challenged.

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
          plug: term() | nil,
          cookies: %{String.t() => String.t()},
          access_token: String.t() | nil
        }

  defstruct base_url: @default_base_url,
            user_agent: @default_user_agent,
            plug: nil,
            cookies: %{},
            access_token: nil

  @doc """
  Builds a client.

  Options:

    * `:base_url` — override the API base URL (defaults to
      `#{@default_base_url}`).
    * `:user_agent` — override the `User-Agent` header for this client only.
    * `:cookies` — a `%{name => value}` map sent as a single `Cookie` header.
    * `:access_token` — sent as an `Authorization: Bearer` header.
    * `:plug` — a `Req.Test` stub (e.g. `{Req.Test, MyStub}`) used to intercept
      requests in tests.
  """
  @spec new(keyword()) :: t()
  def new(opts \\ []) do
    %__MODULE__{
      base_url: Keyword.get(opts, :base_url, @default_base_url),
      user_agent: Keyword.get(opts, :user_agent, user_agent()),
      plug: Keyword.get(opts, :plug),
      cookies: Keyword.get(opts, :cookies, %{}),
      access_token: Keyword.get(opts, :access_token)
    }
  end

  @doc """
  Attaches a session to an existing client.

  Takes `:cookies` and/or `:access_token`; anything not given is left alone, so
  a token can be refreshed without disturbing the cookie jar. Pass `cookies: %{}`
  and `access_token: nil` to clear a session.

      client
      |> ExRecreation.Client.authenticate(cookies: jar, access_token: token)
      |> ExRecreation.month("251864", ~D[2026-11-01])
  """
  @spec authenticate(t(), keyword()) :: t()
  def authenticate(%__MODULE__{} = client, opts) do
    %{
      client
      | cookies: Keyword.get(opts, :cookies, client.cookies),
        access_token: Keyword.get(opts, :access_token, client.access_token)
    }
  end

  @doc "Whether this client carries a session (cookies, a token, or both)."
  @spec authenticated?(t()) :: boolean()
  def authenticated?(%__MODULE__{cookies: cookies, access_token: token}) do
    map_size(cookies) > 0 or is_binary(token)
  end

  @doc "The default User-Agent (overridable via `config :ex_recreation, :user_agent`)."
  @spec user_agent() :: String.t()
  def user_agent, do: Application.get_env(:ex_recreation, :user_agent, @default_user_agent)
end
