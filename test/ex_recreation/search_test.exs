defmodule ExRecreation.SearchTest do
  use ExUnit.Case, async: true

  alias ExRecreation.{Fixtures, Search}

  @stub __MODULE__.Stub

  describe "search/3" do
    test "GETs /search with the query and returns the envelope-less body" do
      Req.Test.stub(@stub, fn conn ->
        assert conn.method == "GET"
        assert conn.request_path == "/api/search"
        assert URI.decode_query(conn.query_string) == %{"q" => "Aravaipa"}

        Req.Test.json(conn, Fixtures.search_payload())
      end)

      assert {:ok, %{"results" => [first | _]}} =
               Search.search(Fixtures.client(@stub), "Aravaipa")

      assert first["entity_id"] == "251864"
      assert first["entity_type"] == "permit"
    end

    test "passes filter and paging params, dropping unknown or nil options" do
      Req.Test.stub(@stub, fn conn ->
        assert URI.decode_query(conn.query_string) == %{
                 "q" => "Aravaipa",
                 "size" => "2",
                 "fq" => "entity_type:permit"
               }

        Req.Test.json(conn, Fixtures.search_payload())
      end)

      assert {:ok, _} =
               Search.search(Fixtures.client(@stub), "Aravaipa",
                 size: 2,
                 fq: "entity_type:permit",
                 start: nil,
                 bogus: "dropped"
               )
    end
  end
end
