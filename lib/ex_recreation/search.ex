defmodule ExRecreation.Search do
  @moduledoc """
  Site-wide search — how you find the permit or campground id everything else
  needs.

  Unlike the rest of the API this endpoint returns a bare top-level object with
  no `"payload"` envelope, so the result is the search response itself:
  `"results"` is the list, and each entry carries `"entity_id"` and
  `"entity_type"` (`"permit"`, `"campground"`, `"recarea"`, …).

      {:ok, %{"results" => [%{"entity_id" => "251864", "entity_type" => "permit"} | _]}} =
        ExRecreation.search(client, "Aravaipa")
  """

  alias ExRecreation.{Client, Request}

  @search_params [:size, :start, :fq, :lat, :lng, :radius, :sort, :exact]

  @doc """
  Searches recreation.gov.

  `GET /api/search?q={query}`

  ## Options

    * `:size` — results per page.
    * `:start` — offset for paging.
    * `:fq` — a filter query, e.g. `"entity_type:permit"`.
    * `:lat` / `:lng` / `:radius` — geographic filter.
    * `:sort` — sort order, e.g. `"score"` or `"available"`.
    * `:exact` — set `true` to require an exact match.
  """
  @spec search(Client.t(), String.t(), keyword()) :: Request.response()
  def search(%Client{} = client, query, opts \\ []) when is_binary(query) do
    params = [q: query] ++ Request.query_params(opts, @search_params)

    Request.request(client, :get, "/search", params: params)
  end
end
