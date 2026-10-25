# ExRecreation

Elixir client for [recreation.gov](https://www.recreation.gov) — live permit and
campground availability, plus the trip-planning predicates you actually want to
ask of it.

These are the same endpoints recreation.gov's own front-end calls. They are
served unauthenticated: no API key, no session, not even a `User-Agent` is
required.

Recreation.gov does publish an official key'd API — [RIDB](https://ridb.recreation.gov) —
but it only serves static metadata (facilities, descriptions, coordinates). It
has no live availability, which is the entire point of this library, so it is
not used here.

## Installation

```elixir
def deps do
  [
    {:ex_recreation, git: "https://github.com/drdray1/ex_recreation.git", tag: "0.2.1"}
  ]
end
```

## Usage

```elixir
client = ExRecreation.new()

# Find the id you need:
{:ok, %{"results" => results}} = ExRecreation.search(client, "Aravaipa")
# => [%{"entity_id" => "251864", "entity_type" => "permit", ...}, ...]

# One month of availability:
{:ok, availability} = ExRecreation.month(client, "251864", ~D[2026-11-01])

# Or a range — one request per calendar month, paced:
{:ok, availability} =
  ExRecreation.range(client, "251864", Date.range(~D[2026-10-01], ~D[2026-12-31]))

# "Are these exact dates bookable for my group?"
ExRecreation.covers?(availability, "772", Date.range(~D[2026-11-12], ~D[2026-11-14]), 10)
#=> false

# "When could we go at all?" — maximal consecutive runs, not every sub-window.
ExRecreation.find_windows(availability, spots: 2, min_days: 3)
#=> [%{division_id: "773", start_date: ~D[2026-11-02], end_date: ~D[2026-11-05],
#      days: 4, min_remaining: 9}]
```

Availability is normalized out of recreation.gov's nested
division → ISO-timestamp envelope into something foldable:

```elixir
%{
  permit_id: "251864",
  next_available_date: ~D[2026-11-02],
  divisions: %{
    "772" => %{
      division_id: "772",
      days: [%{date: ~D[2026-11-01], total: 20, remaining: 0, walkup?: false}, ...]
    }
  }
}
```

## Released vs. sold out

The one thing to internalize about this data: **`total == 0` does not mean sold
out, it means not released yet.** Rolling-window permits only publish a day's
quota once that day enters the booking window. Sold out is `total > 0` with
`remaining == 0`.

The two states are indistinguishable if you only read `remaining`:

```elixir
ExRecreation.released?(availability, "772", range)  # false => not open yet
ExRecreation.covers?(availability, "772", range, 1) # false either way
```

So watching for a **release** means watching `total` go nonzero, while watching
for a **cancellation** means watching `remaining` go nonzero on a day whose
`total` already is.

## Rolling release windows

Permits like Aravaipa Canyon release a new day's quota a fixed number of days
ahead, at a fixed wall-clock time:

```elixir
ExRecreation.release_date(~D[2026-11-12])
#=> ~D[2026-08-13]

ExRecreation.release_at(~D[2026-11-12], zone: "America/Phoenix")
#=> {:ok, #DateTime<2026-08-13 07:00:00-07:00 MST America/Phoenix>}
```

Defaults are a 91-day window and 10:00 a.m. `America/New_York`, which is what
Aravaipa uses. Both are options (`:window_days`, `:release_time`,
`:release_zone`, `:zone`).

`release_at/2` resolves named zones, so it needs a time zone database
(`config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase`, or
`Calendar.put_time_zone_database/1`). `release_date/2` is pure date math and
needs nothing. Every other function in the library is time-zone free.

## The API

| Function | Endpoint |
|---|---|
| `month/3`, `range/4` | `GET /api/permits/{id}/availability/month` |
| `get_permit/2` | `GET /api/permits/{id}` |
| `get_permit_content/2` | `GET /api/permitcontent/{id}` |
| `list_divisions/2`, `division_names/2` | `GET /api/permits/{id}/divisions` |
| `search/3` | `GET /api/search` |

Pure helpers, no request made: `covers?/4`, `min_remaining/3`, `released?/3`,
`find_windows/2`, `release_date/2`, `release_at/2`, `booking_url/2`, `day/3`,
`days/2`, `division_ids/1`.

## Errors

Every call returns `{:ok, term}` or `{:error, reason}`:

| Reason | Meaning |
|---|---|
| `:unauthorized` | 401 — the session is gone, or was never accepted |
| `:not_found` | 404 — bad permit id |
| `:forbidden` | 403 |
| `:rate_limited` | 429 |
| `{:unexpected_status, status}` | any other status ≥ 400 |
| `{:connection_error, reason}` | transport failure |

Real clients retry transient failures and 429s three times with exponential
backoff (500ms, 1s, 2s, 4s). Clients built with a `:plug` disable retries so
stubbed error responses in tests return immediately.

## CLI

```
mix recreation.check --permit 251864 --from 2026-11-12 --to 2026-11-14 --spots 10
```

Prints the day grid, whether the range is covered, the open runs, and when the
first date entered the booking window.

## Sessions

No credentials are required, but a session is accepted. `authenticate/2` hangs a
cookie jar and a bearer token on a client, and every subsequent call carries them
as a `Cookie` header and an `Authorization: Bearer` header:

```elixir
client =
  ExRecreation.new()
  |> ExRecreation.authenticate(cookies: %{"sid" => "..."}, access_token: "...")

ExRecreation.authenticated?(client)
#=> true
```

`authenticate/2` only overwrites what you pass, so a token can be refreshed
without disturbing the jar. `:unauthorized` and `:forbidden` are the two errors
that mean "get a new session".

**This library does not establish a session.** It has no login flow and drives no
browser — it only accepts one obtained elsewhere. That belongs in the calling
application, which is also where the credentials belong.

## Booking

This library reads. It does not book — recreation.gov's terms prohibit automated
reservations, and checkout is CAPTCHA-gated. `booking_url/2` builds a deep link
that lands a human on the availability grid with the right date selected, and
that is the intended end of the automated path. Supplying a session does not
change this: it makes account-scoped reads possible, not checkout.

## Testing

```
mix test
mix test --cover
mix format --check-formatted
mix credo
```

Tests stub HTTP with `Req.Test` via the client's `:plug` field — no network, no
Bypass, no Mox. The fixtures in `test/support/*.json` are real recreation.gov
responses for the Aravaipa Canyon permit, trimmed to a handful of days.

## License

MIT.
