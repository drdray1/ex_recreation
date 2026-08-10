defmodule ExRecreation.PermitsTest do
  use ExUnit.Case, async: true

  alias ExRecreation.{Fixtures, Permits}

  doctest ExRecreation.Permits, only: [booking_url: 2]

  @stub __MODULE__.Stub

  describe "get_permit/2" do
    test "GETs /permits/:id and unwraps the payload" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/permits/251864"

        Req.Test.json(conn, %{
          "payload" => %{"id" => 251_864, "name" => "Aravaipa Canyon Wilderness Permits"}
        })
      end)

      assert {:ok, %{"name" => "Aravaipa Canyon Wilderness Permits"}} =
               Permits.get_permit(Fixtures.client(@stub), "251864")
    end
  end

  describe "get_permit_content/2" do
    test "GETs /permitcontent/:id" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/api/permitcontent/251864"
        Req.Test.json(conn, %{"payload" => %{"description" => %{"description" => "<p>…</p>"}}})
      end)

      assert {:ok, %{"description" => %{"description" => "<p>…</p>"}}} =
               Permits.get_permit_content(Fixtures.client(@stub), "251864")
    end
  end

  describe "list_divisions/2" do
    test "GETs /permits/:id/divisions" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.request_path == "/api/permits/251864/divisions"
        Req.Test.json(conn, Fixtures.divisions_payload())
      end)

      assert {:ok, divisions} = Permits.list_divisions(Fixtures.client(@stub), "251864")
      assert divisions["772"]["name"] == "East Entrance"
    end
  end

  describe "division_names/2" do
    test "reduces divisions to an id => name map" do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, Fixtures.divisions_payload()) end)

      assert {:ok, %{"772" => "East Entrance", "773" => "West Entrance"}} =
               Permits.division_names(Fixtures.client(@stub), "251864")
    end

    test "falls back to the id when a division has no name" do
      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(conn, %{"payload" => %{"772" => %{"id" => "772"}}})
      end)

      assert {:ok, %{"772" => "772"}} = Permits.division_names(Fixtures.client(@stub), "251864")
    end

    test "returns an empty map when the payload is not a division map" do
      Req.Test.stub(@stub, fn conn -> Req.Test.json(conn, %{"payload" => []}) end)

      assert {:ok, %{}} = Permits.division_names(Fixtures.client(@stub), "251864")
    end

    test "skips entries that are not division objects" do
      # Pointed at the wrong endpoint you get a payload of scalars and nested
      # maps; label extraction should degrade rather than raise.
      Req.Test.stub(@stub, fn conn ->
        Req.Test.json(conn, %{
          "payload" => %{
            "permit_id" => "251864",
            "772" => %{"name" => "East Entrance"}
          }
        })
      end)

      assert {:ok, %{"772" => "East Entrance"}} =
               Permits.division_names(Fixtures.client(@stub), "251864")
    end

    test "propagates errors" do
      Req.Test.stub(@stub, fn conn -> Plug.Conn.send_resp(conn, 404, "") end)

      assert {:error, :not_found} = Permits.division_names(Fixtures.client(@stub), "999")
    end
  end

  describe "booking_url/2" do
    test "deep-links to a date" do
      assert Permits.booking_url("251864", ~D[2026-11-12]) ==
               "https://www.recreation.gov/permits/251864/registration/detailed-availability?date=2026-11-12"
    end

    test "falls back to the permit landing page without a date" do
      assert Permits.booking_url("251864") == "https://www.recreation.gov/permits/251864"
      assert Permits.booking_url(251_864) == "https://www.recreation.gov/permits/251864"
    end
  end
end
