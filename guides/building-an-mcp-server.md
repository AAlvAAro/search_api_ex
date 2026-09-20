# Building an MCP server

The [Model Context Protocol](https://modelcontextprotocol.io) asks a server
for a list of tools — each with a name, a description and a JSON Schema — and
then calls them with a map of arguments. `SearchApi.Engine` was built to
answer exactly that, which is why the catalog is compiled in rather than left
in the documentation.

## The whole mapping

```elixir
defmodule MyApp.SearchTools do
  def list_tools do
    for engine <- SearchApi.Engine.list() do
      %{
        name: engine.id,
        description: engine.description,
        inputSchema: SearchApi.Engine.json_schema(engine)
      }
    end
  end

  def call_tool(name, arguments) do
    SearchApi.search(name, arguments)
  end
end
```

That is the entire integration. Three things make it this short:

- **Tool names are engine ids.** `SearchApi.search/3` accepts the string it
  gets back, so no lookup table.
- **Schema properties are parameter names.** The map the model produces is the
  map `search/3` takes, so no argument translation.
- **Validation already happened.** An unknown engine or a missing required
  parameter comes back as an error before a request goes out, so a
  hallucinated tool call costs nothing.

## Choose a subset

151 tools is more than most models handle well, and every engine in the list
is a token cost on every request. Pick the ones your server is actually for:

```elixir
@engines ~w(google google_news google_maps youtube youtube_transcripts google_scholar)

def list_tools do
  for id <- @engines, engine = SearchApi.Engine.fetch!(id) do
    %{name: id, description: engine.description, inputSchema: SearchApi.Engine.json_schema(engine)}
  end
end
```

`SearchApi.Engine.search/1` helps when you want a themed server — everything
shopping, everything social, everything travel:

```elixir
iex> SearchApi.Engine.search("shopping") |> Enum.map(& &1.id)
["bing_product", "bing_shopping", "google_product_page", "google_shopping",
 "google_shopping_autocomplete", "google_shopping_filters"]
```

## Trim the schemas

Some engines document thirty parameters. A model rarely needs all of them,
and every description is context you pay for on each turn. The schema is a
plain map, so narrow it:

```elixir
defp narrow(schema, keep) do
  %{schema | properties: Map.take(schema.properties, keep)}
end

narrow(SearchApi.Engine.json_schema(:google), ~w(q gl hl location page))
```

Keep every name in `schema.required`, or the model will be asked for a tool
call the client rejects locally.

## Per-tenant keys

If the server is multi-tenant, resolve the key per call instead of
configuring one globally:

```elixir
def call_tool(name, arguments, tenant) do
  SearchApi.search(name, arguments, api_key: tenant.search_api_key)
end
```

## Returning errors to the model

MCP wants a tool error the model can act on, not a crash. `SearchApi.Error`
carries a `:reason` that maps cleanly onto what you want the model to do next:

```elixir
def call_tool(name, arguments) do
  case SearchApi.search(name, arguments) do
    {:ok, body} ->
      {:ok, JSON.encode!(body)}

    # The model can fix these itself — tell it what was wrong.
    {:error, %SearchApi.Error{reason: reason} = error}
    when reason in [:unknown_engine, :missing_params] ->
      {:error, Exception.message(error)}

    # These are the operator's problem. Do not invite a retry loop.
    {:error, %SearchApi.Error{} = error} ->
      Logger.error(Exception.message(error))
      {:error, "search is temporarily unavailable"}
  end
end
```

## Keep responses small

A `google` response with every field is tens of kilobytes, most of it
irrelevant to the question being asked. Trim before the result reaches the
model's context:

```elixir
defp summarize(%{"organic_results" => results}) do
  results
  |> Enum.take(10)
  |> Enum.map(&Map.take(&1, ~w(position title link snippet)))
end
```

SearchApi can also do this server-side with its `json_restrictor` parameter,
which saves the bandwidth as well as the tokens — see the
[documentation](https://www.searchapi.io/docs/google). It is passed through
like any other parameter:

```elixir
SearchApi.search(:google, q: "elixir lang", json_restrictor: "organic_results[].{title,link}")
```

## Timeouts

Some engines are slow — flight and hotel searches especially. MCP clients
usually have their own timeout, so set Req's below it and return a clean tool
error rather than letting the client give up first:

```elixir
SearchApi.search(name, arguments, req_options: [receive_timeout: 30_000, retry: false])
```

## Concurrency

The client is stateless and `Req` pools connections through Finch, so
concurrent calls need nothing special:

```elixir
queries
|> Task.async_stream(&SearchApi.search(:google, q: &1), max_concurrency: 10, timeout: 60_000)
|> Enum.to_list()
```

Watch your SearchApi plan's rate limit — a 429 surfaces as
`%SearchApi.Error{reason: :http_error, status: 429}`.
