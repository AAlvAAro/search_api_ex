# SearchApi

[![Hex.pm](https://img.shields.io/hexpm/v/search_api_ex.svg)](https://hex.pm/packages/search_api_ex)
[![Docs](https://img.shields.io/badge/hex-docs-8e7cc3.svg)](https://hexdocs.pm/search_api_ex)
[![License](https://img.shields.io/hexpm/l/search_api_ex.svg)](https://github.com/AAlvAAro/search_api_ex/blob/main/LICENSE)

An Elixir client for [SearchApi.io](https://www.searchapi.io) — real-time
search results as structured JSON from Google, YouTube, Amazon, Maps, TikTok,
LinkedIn, Zillow and **151 engines** in total.

```elixir
SearchApi.search(:google, q: "elixir lang")
SearchApi.search(:youtube_transcripts, video_id: "dQw4w9WgXcQ")
SearchApi.search(:google_maps, q: "coffee", ll: "@40.7455,-74.0083,14z")
```

SearchApi is one endpoint that switches behaviour on an `engine` parameter, so
this is one function. What the library adds on top is a **catalog**: all 151
engines and their 1146 documented parameters, compiled in, queryable at
runtime, and able to emit JSON Schema — which is what makes it drop straight
into an [MCP server](https://hexdocs.pm/search_api_ex/building-an-mcp-server.html).

## Installation

```elixir
def deps do
  [{:search_api_ex, "~> 0.1.0"}]
end
```

## Configuration

Get a key from your [SearchApi dashboard](https://www.searchapi.io/dashboard).

```elixir
config :search_api_ex, api_key: "YOUR_KEY"
```

The key is resolved from the `:api_key` option on the call, then the
application environment, then the `SEARCH_API_KEY` (or `SEARCHAPI_API_KEY`)
environment variable. It
travels as a `Bearer` token rather than a query parameter, so it does not end
up in logs or proxy records.

## Searching

Parameter names are exactly the ones in the
[SearchApi docs](https://www.searchapi.io/docs/google) — nothing is renamed.
Keys can be atoms or strings, values can be any term, `nil` values are
dropped, and lists are joined with commas.

```elixir
{:ok, body} = SearchApi.search(:google, q: "elixir lang", gl: "lt", location: nil)

for result <- body["organic_results"] do
  IO.puts("#{result["position"]}. #{result["title"]} — #{result["link"]}")
end
```

`body` is the decoded JSON for that engine, untouched, plus the
`"search_metadata"` and `"search_parameters"` that SearchApi returns on every
response.

### Errors

```elixir
case SearchApi.search(:google, q: "elixir lang") do
  {:ok, body} -> body
  {:error, %SearchApi.Error{reason: :http_error, status: 429}} -> :rate_limited
  {:error, %SearchApi.Error{} = error} -> Logger.error(Exception.message(error))
end
```

Unknown engines and missing required parameters are caught locally, so a typo
never spends a credit:

```elixir
iex> SearchApi.search(:youtube_transcripts, [])
{:error, %SearchApi.Error{reason: :missing_params, context: ["video_id"], ...}}
```

There is also `SearchApi.search!/3`, which returns the body and raises.

## Discovering engines

```elixir
iex> SearchApi.Engine.search("transcript") |> Enum.map(& &1.id)
["tiktok_transcripts", "youtube_transcripts"]

iex> SearchApi.Engine.fetch!(:google_flights).docs_url
"https://www.searchapi.io/docs/google-flights-api"

iex> SearchApi.Engine.fetch!(:google_flights).params |> Enum.filter(& &1.required)
[%{name: "departure_id", required: true, type: :string, group: "Search Query", doc: "..."}, ...]
```

The [engine list](https://hexdocs.pm/search_api_ex/engines.html) is also
rendered in the docs.

## Building an MCP server

`SearchApi.Engine.json_schema/1` returns a JSON Schema shaped the way MCP
wants a tool's `inputSchema`, and the parameter names it describes are the
same ones `SearchApi.search/3` takes. So a tool listing is a `map`, and a tool
call is a direct dispatch:

```elixir
tools =
  for engine <- SearchApi.Engine.list() do
    %{
      name: engine.id,
      description: engine.description,
      inputSchema: SearchApi.Engine.json_schema(engine)
    }
  end

def call_tool(name, arguments), do: SearchApi.search(name, arguments)
```

The [MCP guide](https://hexdocs.pm/search_api_ex/building-an-mcp-server.html)
covers selecting a useful subset of the 151 engines, per-tenant keys, and
turning `SearchApi.Error` into a tool error.

## Tuning requests

`:req_options` is merged into the underlying [Req](https://hexdocs.pm/req)
request, so timeouts, retries, telemetry and test stubs are Req's, not a
reinvented layer:

```elixir
SearchApi.search(:amazon_search, [q: "keyboard"],
  req_options: [receive_timeout: 90_000, retry: :transient]
)
```

In tests, point Req at a stub and no request leaves the machine:

```elixir
# test_helper.exs
Application.put_env(:search_api_ex, :req_options, plug: {Req.Test, SearchApi})

# your test
Req.Test.stub(SearchApi, fn conn -> Req.Test.json(conn, %{"organic_results" => []}) end)
assert {:ok, %{"organic_results" => []}} = SearchApi.search(:google, q: "x")
```

## Documentation

- [API reference](https://hexdocs.pm/search_api_ex)
- [What changes in Elixir](https://hexdocs.pm/search_api_ex/what-changes-in-elixir.html) — the short list of differences from the HTTP API
- [Building an MCP server](https://hexdocs.pm/search_api_ex/building-an-mcp-server.html)
- [Engines](https://hexdocs.pm/search_api_ex/engines.html) — all 151, with links to the official docs
- [SearchApi documentation](https://www.searchapi.io/docs/google) — the reference for parameters and response shapes

## License

MIT — see [LICENSE](LICENSE).
