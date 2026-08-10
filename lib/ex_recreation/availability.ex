defmodule ExRecreation.Availability do
  @moduledoc """
  Live permit availability — the endpoint that actually matters.

  Recreation.gov returns availability as a map of division id → a map of ISO-8601
  timestamp → quota counts, which is awkward to fold over. `month/3` and
  `range/4` normalize that into atom-keyed maps with real `Date` structs and a
  date-sorted list of days:

      {:ok,
       %{
         permit_id: "251864",
         next_available_date: ~D[2026-11-02],
         divisions: %{
           "772" => %{
             division_id: "772",
             days: [%{date: ~D[2026-11-01], total: 20, remaining: 0, walkup?: false}, ...]
           }
         }
       }}

  ## Reading the numbers

  `total` is the day's quota and `remaining` is what is left. Both matter, and
  they mean different things:

    * `total == 0` — the date has **not been released yet**. Rolling-window
      permits only publish quota once the date enters the booking window.
    * `total > 0` and `remaining == 0` — released and fully booked. This is the
      state a cancellation flips.

  So a `total` going from `0` to nonzero is a *release*, and a `remaining` going
  from `0` to nonzero on an already-released day is a *cancellation*.

  ## Pacing

  `range/4` fetches one request per calendar month and sleeps a randomized
  `page_delay_ms + rand(jitter_ms)` between them. Tune or disable with the
  `:page_delay_ms` / `:jitter_ms` / `:sleep_fn` options.
  """

  alias ExRecreation.{Client, Request}

  @default_page_delay_ms 400
  @default_jitter_ms 400

  @type day :: %{
          date: Date.t(),
          total: non_neg_integer(),
          remaining: non_neg_integer(),
          walkup?: boolean()
        }
  @type division :: %{division_id: String.t(), days: [day()]}
  @type t :: %{
          permit_id: String.t(),
          next_available_date: Date.t() | nil,
          divisions: %{optional(String.t()) => division()}
        }

  @doc """
  Fetches one calendar month of availability for a permit.

  `date` may be any date within the desired month; it is snapped to the first.

  `GET /api/permits/{permit_id}/availability/month?start_date=...`

  Returns `{:ok, t()}` or `{:error, reason}`.
  """
  @spec month(Client.t(), String.t(), Date.t()) :: {:ok, t()} | {:error, term()}
  def month(%Client{} = client, permit_id, %Date{} = date) do
    start_date = date |> Date.beginning_of_month() |> to_start_param()

    client
    |> Request.request(:get, "/permits/#{permit_id}/availability/month",
      params: [start_date: start_date]
    )
    |> case do
      {:ok, payload} -> {:ok, normalize(payload, permit_id)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Fetches every calendar month spanned by `date_range` and merges the result,
  keeping only days that fall inside the range.

  Applies the pacing described in the module doc between month requests.

  ## Options

    * `:page_delay_ms` — base delay between months (default #{@default_page_delay_ms}).
    * `:jitter_ms` — random extra delay ceiling (default #{@default_jitter_ms}).
    * `:sleep_fn` — 1-arity sleeper, injectable for tests (default `Process.sleep/1`).
  """
  @spec range(Client.t(), String.t(), Date.Range.t(), keyword()) :: {:ok, t()} | {:error, term()}
  def range(%Client{} = client, permit_id, %Date.Range{} = date_range, opts \\ []) do
    date_range
    |> months_spanning()
    |> Enum.reduce_while({:ok, []}, fn {month_start, index}, {:ok, acc} ->
      if index > 0, do: pace(opts)

      case month(client, permit_id, month_start) do
        {:ok, result} -> {:cont, {:ok, [result | acc]}}
        {:error, _} = err -> {:halt, err}
      end
    end)
    |> case do
      {:ok, results} -> {:ok, results |> Enum.reverse() |> merge(permit_id, date_range)}
      {:error, _} = err -> err
    end
  end

  @doc """
  Returns the day entry for `division_id` on `date`, or `nil` if the division or
  date is absent from this availability result.
  """
  @spec day(t(), String.t(), Date.t()) :: day() | nil
  def day(availability, division_id, %Date{} = date) do
    availability
    |> days(division_id)
    |> Enum.find(&(&1.date == date))
  end

  @doc "Returns the date-sorted day list for `division_id`, or `[]` if absent."
  @spec days(t(), String.t()) :: [day()]
  def days(%{divisions: divisions}, division_id) do
    case Map.get(divisions, division_id) do
      %{days: days} -> days
      nil -> []
    end
  end

  @doc "Returns the division ids present in this availability result."
  @spec division_ids(t()) :: [String.t()]
  def division_ids(%{divisions: divisions}), do: divisions |> Map.keys() |> Enum.sort()

  # --- Normalization ----------------------------------------------------------

  defp normalize(payload, permit_id) when is_map(payload) do
    %{
      permit_id: to_string(payload["permit_id"] || permit_id),
      next_available_date: parse_date(payload["next_available_date"]),
      divisions: payload |> Map.get("availability", %{}) |> normalize_divisions()
    }
  end

  # Defensive fallback if the envelope shape drifts.
  defp normalize(_payload, permit_id) do
    %{permit_id: permit_id, next_available_date: nil, divisions: %{}}
  end

  defp normalize_divisions(availability) when is_map(availability) do
    Map.new(availability, fn {division_id, division} ->
      {division_id,
       %{
         division_id: to_string(division["division_id"] || division_id),
         days: division |> Map.get("date_availability", %{}) |> normalize_days()
       }}
    end)
  end

  defp normalize_divisions(_), do: %{}

  defp normalize_days(date_availability) when is_map(date_availability) do
    date_availability
    |> Enum.flat_map(fn {timestamp, counts} ->
      case parse_date(timestamp) do
        nil ->
          []

        date ->
          [
            %{
              date: date,
              total: counts["total"] || 0,
              remaining: counts["remaining"] || 0,
              walkup?: counts["show_walkup"] == true
            }
          ]
      end
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  defp normalize_days(_), do: []

  # Merges per-month results into one, dropping days outside the requested range.
  defp merge(results, permit_id, date_range) do
    divisions =
      results
      |> Enum.flat_map(fn %{divisions: divisions} -> Map.to_list(divisions) end)
      |> Enum.group_by(fn {division_id, _} -> division_id end, fn {_, division} -> division end)
      |> Map.new(fn {division_id, divisions} ->
        days =
          divisions
          |> Enum.flat_map(& &1.days)
          |> Enum.filter(&in_range?(&1.date, date_range))
          |> Enum.uniq_by(& &1.date)
          |> Enum.sort_by(& &1.date, Date)

        {division_id, %{division_id: division_id, days: days}}
      end)

    %{
      permit_id: permit_id,
      next_available_date: results |> Enum.find_value(& &1.next_available_date),
      divisions: divisions
    }
  end

  defp in_range?(date, %Date.Range{first: first, last: last}) do
    Date.compare(date, first) != :lt and Date.compare(date, last) != :gt
  end

  # --- Helpers ----------------------------------------------------------------

  # The API wants a UTC-midnight timestamp for the first of the month.
  defp to_start_param(%Date{} = date), do: Date.to_iso8601(date) <> "T00:00:00.000Z"

  # Timestamps arrive as "2026-11-01T00:00:00Z"; only the date part is meaningful.
  defp parse_date(<<date::binary-size(10), _rest::binary>>) do
    case Date.from_iso8601(date) do
      {:ok, parsed} -> parsed
      {:error, _} -> nil
    end
  end

  defp parse_date(_), do: nil

  # First-of-month dates spanning the range, paired with their index.
  defp months_spanning(%Date.Range{first: first, last: last}) do
    first
    |> Date.beginning_of_month()
    |> Stream.iterate(&next_month/1)
    |> Stream.take_while(&(Date.compare(&1, Date.beginning_of_month(last)) != :gt))
    |> Enum.with_index()
  end

  defp next_month(%Date{year: year, month: 12}), do: Date.new!(year + 1, 1, 1)
  defp next_month(%Date{year: year, month: month}), do: Date.new!(year, month + 1, 1)

  defp pace(opts) do
    base = Keyword.get(opts, :page_delay_ms, @default_page_delay_ms)
    jitter = Keyword.get(opts, :jitter_ms, @default_jitter_ms)
    sleep_fn = Keyword.get(opts, :sleep_fn, &Process.sleep/1)

    extra = if jitter > 0, do: :rand.uniform(jitter), else: 0
    sleep_fn.(base + extra)
  end
end
