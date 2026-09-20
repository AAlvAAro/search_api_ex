defmodule SearchApi.EngineTest do
  use ExUnit.Case, async: true

  alias SearchApi.Engine

  doctest SearchApi.Engine

  test "the catalog is non-trivial and every entry is well formed" do
    assert length(Engine.ids()) > 100

    for engine <- Engine.list() do
      assert engine.id =~ ~r/^[a-z0-9_]+$/
      assert engine.name != ""
      assert engine.description != ""
      assert engine.docs_url =~ "https://www.searchapi.io/docs/"
      assert engine.params != []

      for param <- engine.params do
        assert param.name =~ ~r/^[a-zA-Z0-9_\[\]]+$/
        assert is_boolean(param.required)
        assert param.type in [:string, :integer, :boolean]
        assert param.doc != ""
      end
    end
  end

  test "no engine documents the parameters the client sets itself" do
    for engine <- Engine.list(), param <- engine.params do
      refute param.name in ~w(engine api_key)
    end
  end

  test "ids/0 is sorted and matches list/0" do
    assert Engine.ids() == Enum.sort(Engine.ids())
    assert Enum.map(Engine.list(), & &1.id) == Engine.ids()
  end

  test "fetch/1 accepts atoms and strings" do
    assert {:ok, %Engine{id: "google_maps"}} = Engine.fetch(:google_maps)
    assert {:ok, %Engine{id: "google_maps"}} = Engine.fetch("google_maps")
    assert :error = Engine.fetch(:definitely_not_an_engine)
  end

  test "fetch!/1 raises on an unknown engine" do
    assert_raise KeyError, fn -> Engine.fetch!(:definitely_not_an_engine) end
  end

  test "search/1 is case insensitive and matches id, name and description" do
    assert Enum.any?(Engine.search("YOUTUBE"), &(&1.id == "youtube"))
    assert Enum.any?(Engine.search("flight"), &(&1.id == "google_flights"))
    assert Engine.search("zzzznope") == []
  end

  # Regression guard for the catalog. SearchApi's docs mark both halves of an
  # either/or pair "Required"; taking that literally makes a schema that asks a
  # model for a value it must omit, and once made every call look invalid.
  # tools/scrape_engines.py demotes these -- this fails if a rescrape loses it.
  test "params that are only conditionally required are not marked required" do
    for {id, param} <- [
          {:google_maps_place, "data_id"},
          {:google_maps_photos, "data_id"},
          {:google_maps_reviews, "data_id"},
          {:ebay_product, "product_id"},
          {:google_product_page, "product_token"},
          {:airbnb, "bounding_box"},
          {:google_flights, "return_date"},
          {:google_trends, "q"}
        ] do
      names = id |> Engine.fetch!() |> Engine.required_params() |> Enum.map(& &1.name)
      refute param in names, "#{id}.#{param} is conditional and must not be required"
    end
  end

  describe "json_schema/1" do
    test "produces an MCP-shaped input schema" do
      schema = Engine.json_schema(:google)

      assert schema.type == "object"
      assert schema.required == ["q"]
      assert %{type: "string", description: description} = schema.properties["q"]
      assert description =~ "search"
    end

    test "covers every parameter and marks types" do
      engine = Engine.fetch!(:google)
      schema = Engine.json_schema(engine)

      assert map_size(schema.properties) == length(engine.params)
      assert schema.properties["page"].type == "integer"
    end

    test "every engine produces a schema whose required keys are real properties" do
      for engine <- Engine.list() do
        schema = Engine.json_schema(engine)

        for name <- schema.required do
          assert Map.has_key?(schema.properties, name), "#{engine.id}: #{name}"
        end
      end
    end

    test "accepts an id or a struct" do
      assert Engine.json_schema(:google) == Engine.json_schema(Engine.fetch!("google"))
    end

    test "is JSON-encodable, as an MCP tool listing needs" do
      assert Engine.list() |> Enum.map(&Engine.json_schema/1) |> JSON.encode!() |> is_binary()
    end
  end
end
