defmodule ExRecreation.Permits do
  @moduledoc """
  Permit metadata — names, divisions (trailheads / entrances), time zone, and
  the prose that describes the booking rules.

  These return recreation.gov's payloads as-is (string-keyed maps). They are
  large, denormalized, and mostly presentational; normalizing them would throw
  away fields you may well want. The one exception is `division_names/2`, which
  extracts the id → name mapping you almost always actually need.
  """

  alias ExRecreation.{Client, Request}

  @doc """
  Fetches a permit record.

  `GET /api/permits/{permit_id}`

  Useful keys: `"name"`, `"time_zone"`, `"divisions"`, `"has_lottery"`,
  `"latitude"` / `"longitude"`, `"org_name"`.
  """
  @spec get_permit(Client.t(), String.t()) :: Request.response()
  def get_permit(%Client{} = client, permit_id) do
    Request.request(client, :get, "/permits/#{permit_id}")
  end

  @doc """
  Fetches a permit's full content record — everything in `get_permit/2` plus the
  rendered HTML description blocks under `"description"`.

  `GET /api/permitcontent/{permit_id}`

  The `"description"` map is where the booking rules live in prose:
  `"description"` itself carries the rolling-window text, `"cancellation_policy"`
  and `"driving_directions"` are self-explanatory.
  """
  @spec get_permit_content(Client.t(), String.t()) :: Request.response()
  def get_permit_content(%Client{} = client, permit_id) do
    Request.request(client, :get, "/permitcontent/#{permit_id}")
  end

  @doc """
  Fetches the permit's divisions keyed by division id.

  `GET /api/permits/{permit_id}/divisions`

  A "division" is whatever the permit subdivides quota by — for Aravaipa Canyon
  that is the two trailheads (`"772"` East Entrance, `"773"` West Entrance), and
  those ids are what `ExRecreation.Availability` keys its results on.
  """
  @spec list_divisions(Client.t(), String.t()) :: Request.response()
  def list_divisions(%Client{} = client, permit_id) do
    Request.request(client, :get, "/permits/#{permit_id}/divisions")
  end

  @doc """
  The human-facing booking URL for a permit, optionally deep-linked to a date.

  Pure string building — no request is made. This is what you put in a
  notification: it lands on the availability grid with `date` already selected,
  which is as close to the checkout button as an automated tool can get you.

      iex> ExRecreation.Permits.booking_url("251864", ~D[2026-11-12])
      "https://www.recreation.gov/permits/251864/registration/detailed-availability?date=2026-11-12"

      iex> ExRecreation.Permits.booking_url("251864")
      "https://www.recreation.gov/permits/251864"
  """
  @spec booking_url(String.t() | integer(), Date.t() | nil) :: String.t()
  def booking_url(permit_id, date \\ nil)

  def booking_url(permit_id, nil), do: "https://www.recreation.gov/permits/#{permit_id}"

  def booking_url(permit_id, %Date{} = date) do
    booking_url(permit_id) <>
      "/registration/detailed-availability?date=#{Date.to_iso8601(date)}"
  end

  @doc """
  Fetches the permit's divisions and reduces them to an id → name map.

  Returns `{:ok, %{"772" => "East Entrance", "773" => "West Entrance"}}`.

  Entries whose value isn't a division object are skipped rather than raising —
  this feeds UI labels, and an unexpected payload shape should degrade to bare
  division ids, not take the page down with it.
  """
  @spec division_names(Client.t(), String.t()) ::
          {:ok, %{optional(String.t()) => String.t()}} | {:error, term()}
  def division_names(%Client{} = client, permit_id) do
    case list_divisions(client, permit_id) do
      {:ok, divisions} when is_map(divisions) ->
        {:ok,
         divisions
         |> Enum.filter(fn {_id, division} -> is_map(division) end)
         |> Map.new(fn {id, division} -> {id, division["name"] || id} end)}

      {:ok, _other} ->
        {:ok, %{}}

      {:error, _} = err ->
        err
    end
  end
end
