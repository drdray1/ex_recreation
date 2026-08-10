defmodule ExRecreationTest do
  use ExUnit.Case, async: true

  alias ExRecreation.Fixtures

  @stub __MODULE__.Stub

  describe "new/1" do
    test "builds a client" do
      assert %ExRecreation.Client{base_url: "https://www.recreation.gov/api"} = ExRecreation.new()
    end
  end

  describe "availability delegates" do
    test "month/3, day/3, days/2 and division_ids/1 reach Availability" do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.month_payload()) end)

      assert {:ok, availability} =
               ExRecreation.month(Fixtures.client(@stub), "251864", ~D[2026-11-01])

      assert ExRecreation.division_ids(availability) == ["772", "773"]
      assert length(ExRecreation.days(availability, "772")) == 8
      assert %{remaining: 14} = ExRecreation.day(availability, "772", ~D[2026-11-02])
    end

    test "range/4 reaches Availability" do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.month_payload()) end)

      assert {:ok, _} =
               ExRecreation.range(
                 Fixtures.client(@stub),
                 "251864",
                 Date.range(~D[2026-11-02], ~D[2026-11-04])
               )
    end
  end

  describe "trip planning delegates" do
    setup do
      %{
        availability:
          Fixtures.availability(%{
            "772" => [{~D[2026-11-12], 20, 20}, {~D[2026-11-13], 20, 11}]
          })
      }
    end

    test "covers?/4, min_remaining/3 and released?/3 reach Trips", %{availability: availability} do
      range = Date.range(~D[2026-11-12], ~D[2026-11-13])

      assert ExRecreation.covers?(availability, "772", range, 10)
      assert ExRecreation.min_remaining(availability, "772", range) == 11
      assert ExRecreation.released?(availability, "772", range)
    end

    test "find_windows/2 reaches Trips", %{availability: availability} do
      assert [%{division_id: "772", days: 2}] = ExRecreation.find_windows(availability)
    end

    test "release_date/2 and release_at/2 reach Trips" do
      assert ExRecreation.release_date(~D[2026-11-12]) == ~D[2026-08-13]

      assert {:ok, %DateTime{hour: 7}} =
               ExRecreation.release_at(~D[2026-11-12], zone: "America/Phoenix")
    end
  end

  describe "permit and search delegates" do
    test "get_permit/2, get_permit_content/2, list_divisions/2 and division_names/2" do
      Req.Test.stub(@stub, fn conn ->
        case conn.request_path do
          "/api/permits/251864" -> Req.Test.json(conn, %{"payload" => %{"id" => 251_864}})
          "/api/permitcontent/251864" -> Req.Test.json(conn, %{"payload" => %{"id" => 251_864}})
          "/api/permits/251864/divisions" -> Req.Test.json(conn, Fixtures.divisions_payload())
        end
      end)

      client = Fixtures.client(@stub)

      assert {:ok, %{"id" => 251_864}} = ExRecreation.get_permit(client, "251864")
      assert {:ok, %{"id" => 251_864}} = ExRecreation.get_permit_content(client, "251864")
      assert {:ok, %{"772" => _}} = ExRecreation.list_divisions(client, "251864")
      assert {:ok, %{"772" => "East Entrance"}} = ExRecreation.division_names(client, "251864")
    end

    test "booking_url/2 reaches Permits" do
      assert ExRecreation.booking_url("251864", ~D[2026-11-12]) =~ "date=2026-11-12"
      assert ExRecreation.booking_url("251864") == "https://www.recreation.gov/permits/251864"
    end

    test "search/3 reaches Search" do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.search_payload()) end)

      assert {:ok, %{"results" => [_ | _]}} =
               ExRecreation.search(Fixtures.client(@stub), "Aravaipa")
    end
  end
end
