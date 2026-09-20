# What changes in Elixir

The [SearchApi documentation](https://www.searchapi.io/docs/google) is the
reference for what every parameter means and what every response contains.
This library does not restate it, and does not rename anything. This page is
the complete list of things that behave differently when you go through
`SearchApi.search/3` instead of writing the HTTP request yourself.

## Nothing is renamed or reshaped

Parameter names are the documented ones. Response bodies are the documented
ones, decoded into maps with string keys, with nothing stripped or wrapped.

```elixir
# https://www.searchapi.io/api/v1/search?engine=google&q=coffee&gl=lt
SearchApi.search(:google, q: "coffee", gl: "lt")
```

## `engine` and `api_key` are the library's job

Both are set for you, so neither appears in `params`. The engine comes from
the first argument, and the key from configuration.

The key is sent as an `Authorization: Bearer` header rather than a query
parameter. SearchApi accepts both; the header keeps the key out of logs,
proxy access records, and anything else that records URLs.

## Engine ids are atoms or strings

`:google_maps` and `"google_maps"` work everywhere. Atoms read better in code;
strings are what you have when an id arrives from outside, such as an MCP tool
call.

## Parameter values are converted for you

| You write | Sent as | Why |
| --------- | ------- | --- |
| `num: 20` | `num=20` | Any term is stringified, so no manual `to_string/1`. |
| `location: nil` | *omitted* | Optional parameters can be passed through unconditionally. |
| `lang: ["en", "lt"]` | `lang=en,lt` | SearchApi's convention for repeatable filters. |

Note that parameters SearchApi itself expects as JSON strings — Google Hotels'
`property_types`, for instance — still need to be given in the exact form the
documentation shows. The conversions above are for Elixir ergonomics, not a
translation layer.

## Bad calls fail locally

An unknown engine, or a missing required parameter, is rejected before a
request goes out, so a typo does not spend a credit:

```elixir
iex> SearchApi.search(:youtube_transcripts, [])
{:error, %SearchApi.Error{reason: :missing_params, context: ["video_id"]}}
```

Unknown *optional* parameters are passed straight through. SearchApi adds
parameters faster than a client library can follow, and refusing them would
make this library the bottleneck.

## Errors are one struct

Every failure — a missing key, a bad engine, a 429, a TLS timeout — arrives as
`{:error, %SearchApi.Error{}}` with a `:reason` atom to match on. See
`SearchApi.Error` for the list. `SearchApi.search!/3` raises the same struct.

## The catalog is available at runtime

The HTTP API has no endpoint that lists engines or describes their
parameters — that lives only in the documentation. Here it is compiled into
the library:

```elixir
SearchApi.Engine.ids()
SearchApi.Engine.search("shopping")
SearchApi.Engine.fetch!(:google_shopping).params
SearchApi.Engine.json_schema(:google_shopping)
```

This is the one place the library holds information the HTTP API does not, and
the reason it is useful for [building an MCP
server](building-an-mcp-server.html). It is scraped from the official docs at
build time, so it is as current as the release you are running — treat
searchapi.io as authoritative if the two ever disagree.

## Everything else is Req

Timeouts, retries, connection pooling, telemetry, and test stubbing are
[Req](https://hexdocs.pm/req)'s, reached through `:req_options`. There is no
second configuration layer to learn.

```elixir
SearchApi.search(:google, [q: "coffee"], req_options: [retry: :transient])
```

## What this library does not do

- **Pagination.** Every engine paginates differently — `page`, `offset`,
  cursors, `next_page_token`. Follow whatever the engine's docs describe.
- **Response structs.** 151 engines with different response shapes would mean
  151 structs going stale on SearchApi's release schedule. You get the map.
- **Async or batch.** SearchApi's own async endpoints are not wrapped yet.
  `Task.async_stream/3` covers most of what people reach for.
