defmodule ExRecreation.AvailabilityTest do
  use ExUnit.Case, async: true

  alias ExRecreation.{Availability, Fixtures}

  @stub __MODULE__.Stub

  describe "month/3" do
    test "requests the month endpoint with a utc-midnight start_date" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/permits/251864/availability/month"

        assert URI.decode_query(conn.query_string) == %{
                 "start_date" => "2026-11-01T00:00:00.000Z"
               }

        Req.Test.json(conn, Fixtures.month_payload())
      end)

      assert {:ok, _} = Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])
    end

    test "snaps any date in the month back to the first" do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string)["start_date"] == "2026-11-01T00:00:00.000Z"
        Req.Test.json(conn, Fixtures.month_payload())
      end)

      assert {:ok, _} = Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-23])
    end

    test "normalizes the nested envelope into date-sorted days" do
      stub_month(Fixtures.month_payload())

      assert {:ok, availability} =
               Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])

      assert availability.permit_id == "251864"
      assert availability.next_available_date == ~D[2026-11-02]
      assert Availability.division_ids(availability) == ["772", "773"]

      days = Availability.days(availability, "772")
      assert length(days) == 8
      assert Enum.map(days, & &1.date) == Enum.sort(Enum.map(days, & &1.date), Date)

      assert %{date: ~D[2026-11-01], total: 20, remaining: 0, walkup?: false} = hd(days)
    end

    test "day/3 finds a single date and returns nil for anything absent" do
      stub_month(Fixtures.month_payload())

      {:ok, availability} = Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])

      assert %{total: 20, remaining: 14} = Availability.day(availability, "772", ~D[2026-11-02])
      assert Availability.day(availability, "772", ~D[2026-11-30]) == nil
      assert Availability.day(availability, "999", ~D[2026-11-02]) == nil
    end

    test "days/2 returns [] for an unknown division" do
      stub_month(Fixtures.month_payload())

      {:ok, availability} = Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])
      assert Availability.days(availability, "999") == []
    end

    test "tolerates a payload with no availability key" do
      stub_month(%{"payload" => %{"permit_id" => "251864"}})

      assert {:ok, availability} =
               Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])

      assert availability.divisions == %{}
      assert availability.next_available_date == nil
    end

    test "falls back to the requested permit id when the payload shape drifts" do
      stub_month(%{"payload" => "unexpected"})

      assert {:ok, %{permit_id: "251864", divisions: %{}}} =
               Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])
    end

    test "skips date keys it cannot parse rather than crashing" do
      payload = %{
        "payload" => %{
          "permit_id" => "251864",
          "availability" => %{
            "772" => %{
              "division_id" => "772",
              "date_availability" => %{
                "not-a-date" => %{"total" => 1, "remaining" => 1},
                "2026-11-02T00:00:00Z" => %{"total" => 20, "remaining" => 5}
              }
            }
          }
        }
      }

      stub_month(payload)

      {:ok, availability} = Availability.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])
      assert [%{date: ~D[2026-11-02], remaining: 5}] = Availability.days(availability, "772")
    end

    test "propagates errors" do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:error, :not_found} =
               Availability.month(Fixtures.client(@stub), "999999", ~D[2026-11-01])
    end
  end

  describe "range/4" do
    test "fetches one request per calendar month and merges the result" do
      test_pid = self()

      Req.Test.stub(@stub, fn conn ->
        start_date = URI.decode_query(conn.query_string)["start_date"]
        send(test_pid, {:fetched, start_date})

        month =
          case start_date do
            "2026-10-01" <> _ -> october()
            "2026-11-01" <> _ -> Fixtures.month_payload()
            "2026-12-01" <> _ -> december()
          end

        Req.Test.json(conn, month)
      end)

      assert {:ok, availability} =
               Availability.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-10-30], ~D[2026-12-02]),
                 sleep_fn: fn _ -> :ok end
               )

      assert_received {:fetched, "2026-10-01" <> _}
      assert_received {:fetched, "2026-11-01" <> _}
      assert_received {:fetched, "2026-12-01" <> _}

      dates = availability |> Availability.days("772") |> Enum.map(& &1.date)

      # October 30-31 kept, October 1 dropped, November 1-8 kept, December 1-2 kept.
      assert ~D[2026-10-30] in dates
      assert ~D[2026-11-08] in dates
      assert ~D[2026-12-02] in dates
      refute ~D[2026-10-01] in dates
      refute ~D[2026-12-03] in dates
      assert dates == Enum.sort(dates, Date)
    end

    test "paces between months but not before the first" do
      test_pid = self()
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.month_payload()) end)

      assert {:ok, _} =
               Availability.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-10-01], ~D[2026-12-31]),
                 page_delay_ms: 10,
                 jitter_ms: 0,
                 sleep_fn: fn ms -> send(test_pid, {:slept, ms}) end
               )

      # Three months, so two gaps.
      assert_received {:slept, 10}
      assert_received {:slept, 10}
      refute_received {:slept, _}
    end

    test "adds jitter on top of the base delay" do
      test_pid = self()
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.month_payload()) end)

      assert {:ok, _} =
               Availability.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-10-01], ~D[2026-11-30]),
                 page_delay_ms: 10,
                 jitter_ms: 5,
                 sleep_fn: fn ms -> send(test_pid, {:slept, ms}) end
               )

      assert_received {:slept, slept}
      assert slept > 10 and slept <= 15
    end

    test "does not sleep for a single-month range" do
      test_pid = self()
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.month_payload()) end)

      assert {:ok, _} =
               Availability.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-11-02], ~D[2026-11-06]),
                 sleep_fn: fn ms -> send(test_pid, {:slept, ms}) end
               )

      refute_received {:slept, _}
    end

    test "halts and returns the error if any month fails" do
      Req.Test.stub(@stub, fn conn ->
        case URI.decode_query(conn.query_string)["start_date"] do
          "2026-10-01" <> _ -> Req.Test.json(conn, october())
          _ -> Plug.Conn.send_resp(conn, 500, "")
        end
      end)

      assert {:error, {:unexpected_status, 500}} =
               Availability.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-10-01], ~D[2026-11-30]),
                 sleep_fn: fn _ -> :ok end
               )
    end

    test "spans a year boundary" do
      test_pid = self()

      Req.Test.stub(@stub, fn conn ->
        send(test_pid, {:fetched, URI.decode_query(conn.query_string)["start_date"]})
        Req.Test.json(conn, %{"payload" => %{"permit_id" => "251864", "availability" => %{}}})
      end)

      assert {:ok, _} =
               Availability.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-12-15], ~D[2027-01-15]),
                 sleep_fn: fn _ -> :ok end
               )

      assert_received {:fetched, "2026-12-01" <> _}
      assert_received {:fetched, "2027-01-01" <> _}
    end
  end

  defp stub_month(payload) do
    Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, payload) end)
  end

  defp october do
    Fixtures.month_payload_with(%{
      "772" => [{~D[2026-10-01], 20, 5}, {~D[2026-10-30], 20, 6}, {~D[2026-10-31], 20, 7}]
    })
  end

  defp december do
    Fixtures.month_payload_with(%{
      "772" => [{~D[2026-12-01], 20, 8}, {~D[2026-12-02], 20, 9}, {~D[2026-12-03], 20, 10}]
    })
  end
end
