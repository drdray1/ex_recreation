defmodule ExRecreation.Trips do
  @moduledoc """
  Trip planning over a normalized `ExRecreation.Availability` result.

  Pure functions — no HTTP, no client. Everything here operates on the map
  returned by `ExRecreation.Availability.month/3` or `range/4`.

  Two different questions get asked of availability data, and they want
  different shapes:

    * *"Are these exact dates bookable for my group?"* — `covers?/4`. This is
      the predicate a watcher polls on.
    * *"When could my group go at all?"* — `find_windows/2`, which sweeps for
      consecutive runs of bookable days.

  `release_date/2` and `release_at/2` answer a third question that has nothing
  to do with current availability: *when will a future date open for booking?*
  """

  alias ExRecreation.Availability

  @default_window_days 91
  @default_release_time ~T[10:00:00]
  @default_release_zone "America/New_York"

  @type window :: %{
          division_id: String.t(),
          start_date: Date.t(),
          end_date: Date.t(),
          days: pos_integer(),
          min_remaining: non_neg_integer()
        }

  @doc """
  Returns `true` when **every** date in `date_range` has at least `spots`
  remaining in `division_id`.

  A date missing from the availability result counts as not covered, so a range
  that runs past the end of the fetched data is correctly `false` rather than
  accidentally `true`.

      iex> ExRecreation.Trips.covers?(availability, "772", Date.range(~D[2026-11-12], ~D[2026-11-14]), 10)
      false
  """
  @spec covers?(Availability.t(), String.t(), Date.Range.t(), pos_integer()) :: boolean()
  def covers?(availability, division_id, %Date.Range{} = date_range, spots)
      when is_integer(spots) and spots > 0 do
    by_date =
      availability
      |> Availability.days(division_id)
      |> Map.new(&{&1.date, &1})

    Enum.all?(date_range, fn date ->
      case Map.get(by_date, date) do
        %{remaining: remaining} -> remaining >= spots
        nil -> false
      end
    end)
  end

  @doc """
  Returns the smallest `remaining` across `date_range` for `division_id`, or `0`
  if any date in the range is missing from the data.

  Useful for "we need 10 and only 6 are open" partial reporting.
  """
  @spec min_remaining(Availability.t(), String.t(), Date.Range.t()) :: non_neg_integer()
  def min_remaining(availability, division_id, %Date.Range{} = date_range) do
    by_date =
      availability
      |> Availability.days(division_id)
      |> Map.new(&{&1.date, &1})

    Enum.reduce_while(date_range, nil, fn date, acc ->
      case Map.get(by_date, date) do
        %{remaining: remaining} -> {:cont, min(remaining, acc || remaining)}
        nil -> {:halt, 0}
      end
    end) || 0
  end

  @doc """
  Returns `true` when `date_range` is released — every date has a nonzero
  `total` — regardless of whether anything is still left.

  This is what distinguishes "not open for booking yet" from "open and sold
  out", which look identical if you only read `remaining`.
  """
  @spec released?(Availability.t(), String.t(), Date.Range.t()) :: boolean()
  def released?(availability, division_id, %Date.Range{} = date_range) do
    by_date =
      availability
      |> Availability.days(division_id)
      |> Map.new(&{&1.date, &1})

    Enum.all?(date_range, fn date ->
      match?(%{total: total} when total > 0, Map.get(by_date, date))
    end)
  end

  @doc """
  Sweeps for maximal runs of consecutive days that have at least `:spots`
  remaining.

  Returns **maximal** runs rather than every sub-window, so a 5-day run is one
  result with `days: 5` rather than ten overlapping ones. Filter on `days` if
  you need an exact trip length.

  ## Options

    * `:spots` — minimum `remaining` per day (default `1`).
    * `:min_days` — discard runs shorter than this (default `1`).
    * `:divisions` — restrict to these division ids (default: all present).
    * `:between` — a `Date.Range` to restrict the sweep to (default: all dates).

  Results are sorted by start date, then division id.
  """
  @spec find_windows(Availability.t(), keyword()) :: [window()]
  def find_windows(availability, opts \\ []) do
    spots = Keyword.get(opts, :spots, 1)
    min_days = Keyword.get(opts, :min_days, 1)
    between = Keyword.get(opts, :between)

    divisions =
      Keyword.get_lazy(opts, :divisions, fn -> Availability.division_ids(availability) end)

    divisions
    |> Enum.flat_map(fn division_id ->
      availability
      |> Availability.days(division_id)
      |> Enum.filter(&(&1.remaining >= spots and within?(&1.date, between)))
      |> consecutive_runs()
      |> Enum.filter(&(length(&1) >= min_days))
      |> Enum.map(&to_window(&1, division_id))
    end)
    |> Enum.sort_by(&{&1.start_date, &1.division_id}, :asc)
  end

  @doc """
  The date on which `entry_date` enters the booking window.

  Rolling-window permits publish a new day's quota a fixed number of days ahead
  — 91 for Aravaipa Canyon. Pure date math; no time zone database needed.

  ## Options

    * `:window_days` — how far ahead the window reaches (default `#{@default_window_days}`).

      iex> ExRecreation.Trips.release_date(~D[2026-11-12])
      ~D[2026-08-13]
  """
  @spec release_date(Date.t(), keyword()) :: Date.t()
  def release_date(%Date{} = entry_date, opts \\ []) do
    Date.add(entry_date, -Keyword.get(opts, :window_days, @default_window_days))
  end

  @doc """
  The exact moment `entry_date` becomes bookable, as a `DateTime` in the release
  time zone.

  Requires a time zone database (`Calendar.put_time_zone_database/1`, or
  `config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase`) since the
  release time is quoted in Eastern, which observes DST.

  ## Options

    * `:window_days` — how far ahead the window reaches (default `#{@default_window_days}`).
    * `:release_time` — local release time (default `~T[10:00:00]`).
    * `:release_zone` — zone the release time is quoted in (default `"#{@default_release_zone}"`).
    * `:zone` — convert the result into this zone before returning (default: the
      release zone). Pass `"America/Phoenix"` to get the Arizona wall-clock time.

  Returns `{:ok, DateTime.t()}` or `{:error, reason}`.
  """
  @spec release_at(Date.t(), keyword()) :: {:ok, DateTime.t()} | {:error, term()}
  def release_at(%Date{} = entry_date, opts \\ []) do
    date = release_date(entry_date, opts)
    time = Keyword.get(opts, :release_time, @default_release_time)
    release_zone = Keyword.get(opts, :release_zone, @default_release_zone)
    target_zone = Keyword.get(opts, :zone, release_zone)

    with {:ok, datetime} <- DateTime.new(date, time, release_zone) do
      DateTime.shift_zone(datetime, target_zone)
    end
  end

  # --- Internals --------------------------------------------------------------

  defp within?(_date, nil), do: true

  defp within?(date, %Date.Range{first: first, last: last}) do
    Date.compare(date, first) != :lt and Date.compare(date, last) != :gt
  end

  # Chunks a date-sorted day list into runs of calendar-consecutive days.
  defp consecutive_runs(days) do
    Enum.chunk_while(
      days,
      [],
      fn day, acc ->
        case acc do
          [] -> {:cont, [day]}
          [previous | _] when day.date == previous.date -> {:cont, acc}
          [previous | _] -> chunk_or_break(day, previous, acc)
        end
      end,
      fn
        [] -> {:cont, []}
        acc -> {:cont, Enum.reverse(acc), []}
      end
    )
  end

  defp chunk_or_break(day, previous, acc) do
    if Date.diff(day.date, previous.date) == 1 do
      {:cont, [day | acc]}
    else
      {:cont, Enum.reverse(acc), [day]}
    end
  end

  defp to_window(run, division_id) do
    %{
      division_id: division_id,
      start_date: List.first(run).date,
      end_date: List.last(run).date,
      days: length(run),
      min_remaining: run |> Enum.map(& &1.remaining) |> Enum.min()
    }
  end
end
