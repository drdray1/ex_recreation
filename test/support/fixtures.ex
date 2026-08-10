defmodule ExRecreation.Fixtures do
  @moduledoc """
  Test fixtures for ExRecreation.

  The three `*.json` files next to this module are real recreation.gov responses
  for the Aravaipa Canyon permit (251864), trimmed to a handful of days. The
  availability envelope is nested three levels deep and keyed by ISO timestamps;
  hand-writing a convincing one is more error-prone than capturing a real one.
  """

  @permit_id "251864"

  @doc "The Aravaipa Canyon Wilderness permit id, which the fixtures are captured from."
  def permit_id, do: @permit_id

  @doc "A client wired to a `Req.Test` stub."
  def client(stub_name) do
    ExRecreation.new(plug: {Req.Test, stub_name})
  end

  @doc """
  The real month-availability response for November 2026, trimmed to Nov 1–8.

  Division `"772"` (East, quota 20) has every day partly open except Nov 1.
  Division `"773"` (West, quota 30) is sold out on Nov 1, 6 and 7 — useful for
  exercising non-contiguous runs.
  """
  def month_payload, do: read_json("permit_availability_month.json")

  @doc "The real divisions response, trimmed to the fields the library reads."
  def divisions_payload, do: read_json("permit_divisions.json")

  @doc "A real search response — note it has no `\"payload\"` envelope."
  def search_payload, do: read_json("search.json")

  @doc """
  Rebuilds the month payload with different quota numbers, so tests can describe
  the state they care about instead of hunting for a day that happens to match.

  `days` is `%{division_id => [{date, total, remaining}]}`.

      Fixtures.month_payload_with(%{"772" => [{~D[2026-11-12], 20, 20}]})
  """
  def month_payload_with(days) do
    availability =
      Map.new(days, fn {division_id, entries} ->
        {division_id,
         %{
           "division_id" => division_id,
           "date_availability" =>
             Map.new(entries, fn {date, total, remaining} ->
               {Date.to_iso8601(date) <> "T00:00:00Z",
                %{
                  "total" => total,
                  "remaining" => remaining,
                  "show_walkup" => false,
                  "is_secret_quota" => false
                }}
             end)
         }}
      end)

    %{
      "payload" => %{
        "permit_id" => @permit_id,
        "next_available_date" => nil,
        "availability" => availability
      }
    }
  end

  @doc """
  Builds a normalized availability map directly, for testing `ExRecreation.Trips`
  without going through HTTP.

  `days` is `%{division_id => [{date, total, remaining}]}`.
  """
  def availability(days) do
    %{
      permit_id: @permit_id,
      next_available_date: nil,
      divisions:
        Map.new(days, fn {division_id, entries} ->
          {division_id,
           %{
             division_id: division_id,
             days:
               entries
               |> Enum.map(fn {date, total, remaining} ->
                 %{date: date, total: total, remaining: remaining, walkup?: false}
               end)
               |> Enum.sort_by(& &1.date, Date)
           }}
        end)
    }
  end

  defp read_json(name) do
    __DIR__
    |> Path.join(name)
    |> File.read!()
    |> Jason.decode!()
  end
end
