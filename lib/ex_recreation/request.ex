defmodule ExRecreation.Request do
  @moduledoc """
  Low-level HTTP for an `ExRecreation.Client`.

  Every request hits the client's `base_url`, carries a browser-ish
  `User-Agent`, and is normalized to `{:ok, payload}` / `{:error, reason}` by
  `handle_response/1`. Transient errors and `429`s are retried with exponential
  backoff in the real client and disabled under a test plug so stubbed responses
  return deterministically.

  Recreation.gov wraps every successful body in a `"payload"` envelope;
  `handle_response/1` unwraps it so callers never see it.
  """

  alias ExRecreation.Client

  @type response :: {:ok, term()} | {:error, term()}

  @doc """
  Builds a query-params keyword list from `opts`, keeping only `allowed` keys
  with non-nil values.
  """
  @spec query_params(keyword(), [atom()]) :: keyword()
  def query_params(opts, allowed) do
    for key <- allowed, value = opts[key], value != nil, do: {key, value}
  end

  @doc """
  Performs `method` against `path` (relative to the client `base_url`) and
  normalizes the response. Pass query params with `opts[:params]`.
  """
  @spec request(Client.t(), atom(), String.t(), keyword()) :: response()
  def request(%Client{} = client, method, path, opts \\ []) do
    client
    |> options(method, path, opts)
    |> Req.request()
    |> handle_response()
  end

  @doc """
  The `Req` options `request/4` will use.

  Split out from `request/4` so the retry policy is inspectable without making a
  request. Real clients retry transient failures and `429`s three times with
  exponential backoff (500ms, 1s, 2s, 4s); clients wired to a test plug disable
  retries entirely, so a stubbed error response comes back immediately instead
  of sleeping through a backoff schedule.
  """
  @spec options(Client.t(), atom(), String.t(), keyword()) :: keyword()
  def options(%Client{} = client, method, path, opts \\ []) do
    [
      method: method,
      base_url: client.base_url,
      url: path,
      headers: headers(client)
    ]
    |> Keyword.merge(retry_opts(client.plug))
    |> maybe_put(:json, Keyword.get(opts, :json))
    |> maybe_put(:params, Keyword.get(opts, :params))
    |> maybe_plug(client.plug)
  end

  @doc """
  Normalizes a recreation.gov response to `{:ok, payload}` or `{:error, reason}`.

  Successful bodies come wrapped as `%{"payload" => ...}` and are unwrapped.
  Anything else 2xx is returned as-is, which covers `/api/search` — the one
  endpoint that returns a bare top-level object with no envelope.
  """
  @spec handle_response({:ok, Req.Response.t()} | {:error, term()}) :: response()
  def handle_response({:ok, %Req.Response{status: status, body: %{"payload" => payload}}})
      when status in 200..299,
      do: {:ok, payload}

  def handle_response({:ok, %Req.Response{status: status, body: body}})
      when status in 200..299,
      do: {:ok, body}

  def handle_response({:ok, %Req.Response{status: 403}}), do: {:error, :forbidden}
  def handle_response({:ok, %Req.Response{status: 404}}), do: {:error, :not_found}
  def handle_response({:ok, %Req.Response{status: 429}}), do: {:error, :rate_limited}

  def handle_response({:ok, %Req.Response{status: status}}) when status >= 400,
    do: {:error, {:unexpected_status, status}}

  def handle_response({:error, reason}), do: {:error, {:connection_error, reason}}

  # --- Headers ----------------------------------------------------------------

  defp headers(%Client{user_agent: user_agent}) do
    [
      {"user-agent", user_agent},
      {"accept", "application/json"}
    ]
  end

  # Retry transient errors / 429s in the real client; disable under a test plug
  # so stubbed error responses return immediately and deterministically.
  defp retry_opts(nil),
    do: [retry: :transient, max_retries: 3, retry_delay: &retry_delay/1]

  defp retry_opts(_plug), do: [retry: false]

  # Exponential backoff for transient errors / 429s.
  defp retry_delay(attempt), do: 500 * Integer.pow(2, attempt)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp maybe_plug(opts, nil), do: opts
  defp maybe_plug(opts, plug), do: Keyword.put(opts, :plug, plug)
end
