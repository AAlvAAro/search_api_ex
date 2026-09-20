defmodule SearchApi.Engine do
  @moduledoc """
  The engine catalog: every SearchApi engine, its parameters, and their docs.

  SearchApi exposes one HTTP endpoint and selects behaviour with an `engine`
  parameter. This module is the compiled-in catalog of those engines, scraped
  from the [official documentation](https://www.searchapi.io/docs/google) and
  baked into the library at build time — no network call, no runtime file read.

  It exists so that callers can *discover* engines at runtime rather than
  hard-coding them. That is what makes `SearchApi` straightforward to expose as
  an MCP server, a CLI, or a LiveView form: see `json_schema/1`.

      iex> engine = SearchApi.Engine.fetch!("youtube_transcripts")
      iex> engine.name
      "YouTube Transcripts"
      iex> Enum.map(SearchApi.Engine.required_params(engine), & &1.name)
      ["video_id"]

  ## Parameters

  Each parameter is a plain map:

      %{
        name: "video_id",
        required: true,
        type: :string,
        group: "Search Query",
        doc: "Parameter defines the video_id you want to search. ..."
      }

  `:type` is inferred from the documentation (`:string`, `:integer` or
  `:boolean`) and is a hint for schema generation, not a validation rule —
  every value is sent to SearchApi as a query string either way.
  """

  @enforce_keys [:id, :name, :description, :docs_url, :params]
  defstruct [:id, :name, :description, :docs_url, :params]

  @type param :: %{
          name: String.t(),
          required: boolean(),
          type: :string | :integer | :boolean,
          group: String.t(),
          doc: String.t()
        }

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          description: String.t(),
          docs_url: String.t(),
          params: [param()]
        }

  catalog_path = Path.expand("../../priv/engines.json", __DIR__)
  @external_resource catalog_path

  @catalog catalog_path
           |> File.read!()
           |> JSON.decode!()
           |> Map.new(fn {id, e} ->
             {
               id,
               # ponytail: literal __struct__ key because %__MODULE__{} cannot be
               # expanded in the body of the module that defines the struct.
               %{
                 __struct__: __MODULE__,
                 id: id,
                 name: e["name"],
                 description: e["description"],
                 docs_url: e["docs_url"],
                 params:
                   Enum.map(e["params"], fn p ->
                     %{
                       name: p["name"],
                       required: p["required"],
                       type: String.to_atom(p["type"]),
                       group: p["group"],
                       doc: p["doc"]
                     }
                   end)
               }
             }
           end)

  @ids @catalog |> Map.keys() |> Enum.sort()

  @doc """
  Every engine id, sorted.

      iex> "google" in SearchApi.Engine.ids()
      true

      iex> length(SearchApi.Engine.ids())
      151
  """
  @spec ids() :: [String.t()]
  def ids, do: @ids

  @doc """
  Every engine, sorted by id.
  """
  @spec list() :: [t()]
  def list, do: Enum.map(@ids, &@catalog[&1])

  @doc """
  Look up one engine.

  Accepts an atom or a string, so `:google_maps` and `"google_maps"` are
  interchangeable everywhere in this library.

      iex> {:ok, engine} = SearchApi.Engine.fetch(:google_maps)
      iex> engine.id
      "google_maps"

      iex> SearchApi.Engine.fetch("nope")
      :error
  """
  @spec fetch(atom() | String.t()) :: {:ok, t()} | :error
  def fetch(id) when is_atom(id), do: fetch(Atom.to_string(id))
  def fetch(id) when is_binary(id), do: Map.fetch(@catalog, id)

  @doc """
  Same as `fetch/1` but raises `KeyError` on an unknown engine.
  """
  @spec fetch!(atom() | String.t()) :: t()
  def fetch!(id) do
    case fetch(id) do
      {:ok, engine} -> engine
      :error -> raise KeyError, key: to_string(id), term: __MODULE__
    end
  end

  @doc """
  The parameters an engine requires.

      iex> SearchApi.Engine.fetch!(:google) |> SearchApi.Engine.required_params() |> Enum.map(& &1.name)
      ["q"]
  """
  @spec required_params(t()) :: [param()]
  def required_params(%__MODULE__{params: params}), do: Enum.filter(params, & &1.required)

  @doc """
  Full-text search over engine ids, names and descriptions.

      iex> SearchApi.Engine.search("transcript") |> Enum.map(& &1.id)
      ["tiktok_transcripts", "youtube_transcripts"]
  """
  @spec search(String.t()) :: [t()]
  def search(query) do
    q = String.downcase(query)

    Enum.filter(list(), fn e ->
      String.contains?(String.downcase("#{e.id} #{e.name} #{e.description}"), q)
    end)
  end

  @doc """
  A [JSON Schema](https://json-schema.org) object describing an engine's parameters.

  The shape matches what the Model Context Protocol expects for a tool's
  `inputSchema`, which makes wiring the catalog into an MCP server a one-liner
  per engine:

      for engine <- SearchApi.Engine.list() do
        %{
          name: engine.id,
          description: engine.description,
          inputSchema: SearchApi.Engine.json_schema(engine)
        }
      end

  Then dispatch the tool call straight to `SearchApi.search/3` — the parameter
  names are identical.

      iex> schema = SearchApi.Engine.json_schema(:youtube_transcripts)
      iex> schema.required
      ["video_id"]
      iex> schema.properties["video_id"].type
      "string"
  """
  @spec json_schema(t() | atom() | String.t()) :: map()
  def json_schema(%__MODULE__{} = engine) do
    %{
      type: "object",
      properties:
        Map.new(engine.params, fn p ->
          {p.name, %{type: Atom.to_string(p.type), description: p.doc}}
        end),
      required: engine |> required_params() |> Enum.map(& &1.name)
    }
  end

  def json_schema(id), do: id |> fetch!() |> json_schema()
end
