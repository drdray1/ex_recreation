defmodule Mix.Tasks.Recreation.Check do
  @shortdoc "Print live recreation.gov availability for a permit and date range"

  @moduledoc """
  One-shot availability probe against the live recreation.gov API.

  Handy for answering "what does it look like *right now*" without opening
  `iex`, and for sanity-checking a watcher's view of the world against reality.

      mix recreation.check --permit 251864 --from 2026-11-12 --to 2026-11-14 --spots 10

  ## Options

    * `--permit` — permit id (default `251864`, Aravaipa Canyon Wilderness).
    * `--from` / `--to` — ISO dates bounding the range (default: today through
      today + 120 days).
    * `--spots` — how many spots the trip needs (default `1`). Days that clear it
      are marked `*`.
    * `--division` — restrict to one division id; repeatable.
    * `--window-days` — rolling release window for the countdown (default `91`).

  Reads only. Makes one request per calendar month spanned, paced.
  """

  use Mix.Task

  @default_permit "251864"
  @switches [
    permit: :string,
    from: :string,
    to: :string,
    spots: :integer,
    division: :keep,
    window_days: :integer
  ]

  @impl Mix.Task
  def run(argv) do
    Application.ensure_all_started(:req)
    {opts, _argv} = OptionParser.parse!(argv, strict: @switches)

    permit_id = Keyword.get(opts, :permit, @default_permit)
    spots = Keyword.get(opts, :spots, 1)
    from = date_option(opts, :from, Date.utc_today())
    to = date_option(opts, :to, Date.add(Date.utc_today(), 120))
    range = Date.range(from, to)

    client = ExRecreation.new()

    case ExRecreation.range(client, permit_id, range) do
      {:ok, availability} -> report(client, availability, permit_id, range, spots, opts)
      {:error, reason} -> Mix.raise("recreation.gov request failed: #{inspect(reason)}")
    end
  end

  defp report(client, availability, permit_id, range, spots, opts) do
    names = division_names(client, permit_id)

    divisions =
      case Keyword.get_values(opts, :division) do
        [] -> ExRecreation.division_ids(availability)
        ids -> ids
      end

    Mix.shell().info("permit #{permit_id} — #{range.first} to #{range.last}, needing #{spots}")
    Mix.shell().info("")

    for division_id <- divisions do
      name = Map.get(names, division_id, division_id)
      Mix.shell().info("#{name} (#{division_id})")

      availability
      |> ExRecreation.days(division_id)
      |> Enum.each(&Mix.shell().info(format_day(&1, spots)))

      covered? = ExRecreation.covers?(availability, division_id, range, spots)
      Mix.shell().info("  => covers #{range.first}..#{range.last} for #{spots}: #{covered?}")
      Mix.shell().info("")
    end

    report_windows(availability, divisions, spots)
    report_release(range.first, opts)
  end

  defp report_windows(availability, divisions, spots) do
    Mix.shell().info("open runs (>= #{spots} spots):")

    case ExRecreation.find_windows(availability, spots: spots, divisions: divisions) do
      [] ->
        Mix.shell().info("  none")

      windows ->
        for window <- windows do
          Mix.shell().info(
            "  #{window.division_id}  #{window.start_date}..#{window.end_date}" <>
              "  #{window.days}d  min #{window.min_remaining}"
          )
        end
    end
  end

  defp report_release(entry_date, opts) do
    release_opts = Keyword.take(opts, [:window_days])
    release_date = ExRecreation.release_date(entry_date, release_opts)

    Mix.shell().info("")
    Mix.shell().info("#{entry_date} entered the booking window on #{release_date}")

    case ExRecreation.release_at(entry_date, release_opts) do
      {:ok, datetime} -> Mix.shell().info("  release moment: #{datetime}")
      # No time zone database configured — the date above is still useful.
      {:error, _reason} -> :ok
    end
  end

  defp format_day(day, spots) do
    marker = if day.remaining >= spots, do: "*", else: " "
    state = if day.total == 0, do: "unreleased", else: "#{day.remaining}/#{day.total}"

    "  #{marker} #{day.date}  #{state}"
  end

  defp division_names(client, permit_id) do
    case ExRecreation.division_names(client, permit_id) do
      {:ok, names} -> names
      {:error, _} -> %{}
    end
  end

  defp date_option(opts, key, default) do
    case Keyword.get(opts, key) do
      nil ->
        default

      value ->
        case Date.from_iso8601(value) do
          {:ok, date} -> date
          {:error, _} -> Mix.raise("--#{key} must be an ISO date (YYYY-MM-DD), got: #{value}")
        end
    end
  end
end
