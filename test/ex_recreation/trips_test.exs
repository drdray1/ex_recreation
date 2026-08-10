defmodule ExRecreation.TripsTest do
  use ExUnit.Case, async: true

  alias ExRecreation.{Fixtures, Trips}

  doctest ExRecreation.Trips, only: [release_date: 2]

  # East (772): Nov 12-14 wide open. West (773): Nov 13 short, Nov 14 missing.
  defp target_availability do
    Fixtures.availability(%{
      "772" => [
        {~D[2026-11-12], 20, 20},
        {~D[2026-11-13], 20, 18},
        {~D[2026-11-14], 20, 11}
      ],
      "773" => [
        {~D[2026-11-12], 30, 30},
        {~D[2026-11-13], 30, 6}
      ]
    })
  end

  @target Date.range(~D[2026-11-12], ~D[2026-11-14])

  describe "covers?/4" do
    test "is true when every day in the range clears the spot count" do
      assert Trips.covers?(target_availability(), "772", @target, 10)
      assert Trips.covers?(target_availability(), "772", @target, 11)
    end

    test "is false when any single day falls short" do
      refute Trips.covers?(target_availability(), "772", @target, 12)
    end

    test "is false when a day in the range is missing entirely" do
      # West has no Nov 14 row at all, so the range runs off the end of the data.
      refute Trips.covers?(target_availability(), "773", @target, 1)
    end

    test "is false for an unknown division" do
      refute Trips.covers?(target_availability(), "999", @target, 1)
    end

    test "treats an unreleased day as not covered" do
      availability = Fixtures.availability(%{"772" => [{~D[2026-11-12], 0, 0}]})
      refute Trips.covers?(availability, "772", Date.range(~D[2026-11-12], ~D[2026-11-12]), 1)
    end
  end

  describe "min_remaining/3" do
    test "returns the tightest day in the range" do
      assert Trips.min_remaining(target_availability(), "772", @target) == 11
    end

    test "returns 0 when any day in the range is missing" do
      assert Trips.min_remaining(target_availability(), "773", @target) == 0
    end

    test "returns 0 for an unknown division" do
      assert Trips.min_remaining(target_availability(), "999", @target) == 0
    end

    test "handles a single-day range" do
      range = Date.range(~D[2026-11-13], ~D[2026-11-13])
      assert Trips.min_remaining(target_availability(), "773", range) == 6
    end
  end

  describe "released?/3" do
    test "distinguishes sold out from not yet released" do
      sold_out = Fixtures.availability(%{"772" => [{~D[2026-11-12], 20, 0}]})
      unreleased = Fixtures.availability(%{"772" => [{~D[2026-11-12], 0, 0}]})
      range = Date.range(~D[2026-11-12], ~D[2026-11-12])

      assert Trips.released?(sold_out, "772", range)
      refute Trips.released?(unreleased, "772", range)

      # Both look identical if you only read `remaining` — that is the point.
      refute Trips.covers?(sold_out, "772", range, 1)
      refute Trips.covers?(unreleased, "772", range, 1)
    end

    test "is false when part of the range is unreleased" do
      availability =
        Fixtures.availability(%{
          "772" => [{~D[2026-11-12], 20, 4}, {~D[2026-11-13], 0, 0}]
        })

      refute Trips.released?(availability, "772", Date.range(~D[2026-11-12], ~D[2026-11-13]))
    end

    test "is false when a day is missing" do
      refute Trips.released?(target_availability(), "773", @target)
    end
  end

  describe "find_windows/2" do
    test "returns maximal consecutive runs, not every sub-window" do
      availability =
        Fixtures.availability(%{
          "772" => [
            {~D[2026-11-01], 20, 5},
            {~D[2026-11-02], 20, 7},
            {~D[2026-11-03], 20, 6}
          ]
        })

      assert [window] = Trips.find_windows(availability)

      assert window == %{
               division_id: "772",
               start_date: ~D[2026-11-01],
               end_date: ~D[2026-11-03],
               days: 3,
               min_remaining: 5
             }
    end

    test "breaks a run where a day is sold out" do
      availability =
        Fixtures.availability(%{
          "772" => [
            {~D[2026-11-01], 20, 5},
            {~D[2026-11-02], 20, 0},
            {~D[2026-11-03], 20, 6},
            {~D[2026-11-04], 20, 6}
          ]
        })

      assert [first, second] = Trips.find_windows(availability)
      assert first.start_date == ~D[2026-11-01] and first.days == 1
      assert second.start_date == ~D[2026-11-03] and second.days == 2
    end

    test "breaks a run across a calendar gap" do
      availability =
        Fixtures.availability(%{
          "772" => [{~D[2026-11-01], 20, 5}, {~D[2026-11-05], 20, 5}]
        })

      assert [_, _] = Trips.find_windows(availability)
    end

    test "filters by spots" do
      availability =
        Fixtures.availability(%{
          "772" => [{~D[2026-11-01], 20, 3}, {~D[2026-11-02], 20, 12}]
        })

      assert [%{start_date: ~D[2026-11-02], days: 1}] =
               Trips.find_windows(availability, spots: 10)

      assert [%{days: 2}] = Trips.find_windows(availability, spots: 3)
    end

    test "filters by min_days" do
      availability =
        Fixtures.availability(%{
          "772" => [
            {~D[2026-11-01], 20, 5},
            {~D[2026-11-03], 20, 5},
            {~D[2026-11-04], 20, 5},
            {~D[2026-11-05], 20, 5}
          ]
        })

      assert [%{days: 3, start_date: ~D[2026-11-03]}] =
               Trips.find_windows(availability, min_days: 2)
    end

    test "restricts to the given divisions" do
      availability =
        Fixtures.availability(%{
          "772" => [{~D[2026-11-01], 20, 5}],
          "773" => [{~D[2026-11-01], 30, 5}]
        })

      assert [%{division_id: "773"}] = Trips.find_windows(availability, divisions: ["773"])
      assert length(Trips.find_windows(availability)) == 2
    end

    test "restricts to a date range" do
      availability =
        Fixtures.availability(%{
          "772" => [
            {~D[2026-11-01], 20, 5},
            {~D[2026-11-02], 20, 5},
            {~D[2026-11-03], 20, 5}
          ]
        })

      windows =
        Trips.find_windows(availability, between: Date.range(~D[2026-11-02], ~D[2026-11-02]))

      assert [%{start_date: ~D[2026-11-02], end_date: ~D[2026-11-02], days: 1}] = windows
    end

    test "sorts by start date then division" do
      availability =
        Fixtures.availability(%{
          "773" => [{~D[2026-11-01], 30, 5}],
          "772" => [{~D[2026-11-01], 20, 5}, {~D[2026-11-03], 20, 5}]
        })

      assert [
               %{start_date: ~D[2026-11-01], division_id: "772"},
               %{start_date: ~D[2026-11-01], division_id: "773"},
               %{start_date: ~D[2026-11-03], division_id: "772"}
             ] = Trips.find_windows(availability)
    end

    test "returns [] when nothing is open" do
      availability = Fixtures.availability(%{"772" => [{~D[2026-11-01], 20, 0}]})
      assert Trips.find_windows(availability) == []
    end

    test "returns [] for an availability result with no divisions" do
      assert Trips.find_windows(Fixtures.availability(%{})) == []
    end
  end

  describe "release_date/2" do
    test "defaults to a 91-day rolling window" do
      assert Trips.release_date(~D[2026-11-12]) == ~D[2026-08-13]
      assert Trips.release_date(~D[2026-11-14]) == ~D[2026-08-15]
    end

    test "accepts a different window" do
      assert Trips.release_date(~D[2026-11-12], window_days: 180) == ~D[2026-05-16]
      assert Trips.release_date(~D[2026-11-12], window_days: 0) == ~D[2026-11-12]
    end
  end

  describe "release_at/2" do
    test "resolves Aravaipa's 10am Eastern drop to 7am Arizona time" do
      assert {:ok, phoenix} = Trips.release_at(~D[2026-11-12], zone: "America/Phoenix")

      assert phoenix.year == 2026 and phoenix.month == 8 and phoenix.day == 13
      assert phoenix.hour == 7 and phoenix.minute == 0
      assert phoenix.time_zone == "America/Phoenix"
    end

    test "defaults to returning the release zone itself" do
      assert {:ok, eastern} = Trips.release_at(~D[2026-11-12])

      assert eastern.hour == 10
      assert eastern.time_zone == "America/New_York"
      assert eastern.zone_abbr == "EDT"
    end

    test "tracks the eastern DST shift that Arizona does not observe" do
      # A January entry date releases in October (EDT); a May one releases in
      # February (EST). Arizona stays on MST year round, so the local Arizona
      # hour moves even though the Eastern hour does not.
      {:ok, from_edt} = Trips.release_at(~D[2027-01-15], zone: "America/Phoenix")
      {:ok, from_est} = Trips.release_at(~D[2027-05-15], zone: "America/Phoenix")

      assert from_edt.hour == 7
      assert from_est.hour == 8
    end

    test "accepts a custom release time and window" do
      assert {:ok, datetime} =
               Trips.release_at(~D[2026-11-12],
                 window_days: 30,
                 release_time: ~T[07:00:00],
                 release_zone: "America/Los_Angeles"
               )

      assert datetime.month == 10 and datetime.day == 13
      assert datetime.hour == 7
      assert datetime.time_zone == "America/Los_Angeles"
    end

    test "returns an error for an unknown zone" do
      assert {:error, _} = Trips.release_at(~D[2026-11-12], release_zone: "Mars/Olympus_Mons")
    end
  end
end
