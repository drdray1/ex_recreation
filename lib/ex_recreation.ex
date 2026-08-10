defmodule ExRecreation do
  @moduledoc """
  Elixir client for [recreation.gov](https://www.recreation.gov) — live permit
  and campground availability.

  These are the same endpoints recreation.gov's own front-end calls. They are
  served unauthenticated: no API key, no session, not even a `User-Agent`. (The
  *official* key'd API, RIDB, only serves static metadata and has no live
  availability, so it is not used here.)

  ## Usage

      client = ExRecreation.new()

      # Find the permit id you care about:
      {:ok, %{"results" => results}} = ExRecreation.search(client, "Aravaipa")

      # Pull a month of availability:
      {:ok, availability} = ExRecreation.month(client, "251864", ~D[2026-11-01])

      # Ask the question you actually have:
      ExRecreation.covers?(availability, "772", Date.range(~D[2026-11-12], ~D[2026-11-14]), 10)
      #=> false

      # Or sweep for anything that would work:
      ExRecreation.find_windows(availability, spots: 2, min_days: 3)
      #=> [%{division_id: "773", start_date: ~D[2026-11-02], end_date: ~D[2026-11-05], days: 4, min_remaining: 9}]

  Ranges spanning several months fetch one request per month, paced:

      {:ok, availability} =
        ExRecreation.range(client, "251864", Date.range(~D[2026-10-01], ~D[2026-12-31]))

  ## Released vs. sold out

  The single most important thing to understand about this data: `total == 0`
  does **not** mean sold out, it means *not released yet*. Rolling-window
  permits only publish a day's quota once that day enters the booking window.
  Sold out is `total > 0` with `remaining == 0`.

  So watching for a permit drop means watching `total` go nonzero, while
  watching for a cancellation means watching `remaining` go nonzero on a day
  whose `total` is already nonzero. `ExRecreation.Trips.released?/3` and
  `covers?/4` distinguish the two.

  ## When does a date open?

  For rolling-window permits, `ExRecreation.Trips` computes it:

      ExRecreation.release_date(~D[2026-11-12])
      #=> ~D[2026-08-13]

      ExRecreation.release_at(~D[2026-11-12], zone: "America/Phoenix")
      #=> {:ok, ~U[2026-08-13 14:00:00Z] in America/Phoenix — 7:00 a.m. MST}

  The default window is 91 days and the default release time is 10:00 a.m.
  Eastern, which is what Aravaipa Canyon uses. Both are options.

  ## Errors

  Every call returns `{:ok, term}` or `{:error, reason}`, where `reason` is one
  of `:not_found`, `:forbidden`, `:rate_limited`, `{:unexpected_status, status}`,
  or `{:connection_error, reason}`.

  ## A note on booking

  This library reads. It does not book — recreation.gov's terms prohibit
  automated reservations and checkout is CAPTCHA-gated. `booking_url/2` gets a
  human to the right page with the right date selected, and that is the intended
  end of the automated path.
  """

  alias ExRecreation.{Availability, Client, Permits, Search, Trips}

  defdelegate new(opts \\ []), to: Client

  defdelegate month(client, permit_id, date), to: Availability
  defdelegate range(client, permit_id, date_range, opts \\ []), to: Availability
  defdelegate day(availability, division_id, date), to: Availability
  defdelegate days(availability, division_id), to: Availability
  defdelegate division_ids(availability), to: Availability

  defdelegate covers?(availability, division_id, date_range, spots), to: Trips
  defdelegate min_remaining(availability, division_id, date_range), to: Trips
  defdelegate released?(availability, division_id, date_range), to: Trips
  defdelegate find_windows(availability, opts \\ []), to: Trips
  defdelegate release_date(entry_date, opts \\ []), to: Trips
  defdelegate release_at(entry_date, opts \\ []), to: Trips

  defdelegate get_permit(client, permit_id), to: Permits
  defdelegate get_permit_content(client, permit_id), to: Permits
  defdelegate list_divisions(client, permit_id), to: Permits
  defdelegate division_names(client, permit_id), to: Permits
  defdelegate booking_url(permit_id, date \\ nil), to: Permits

  defdelegate search(client, query, opts \\ []), to: Search
end
