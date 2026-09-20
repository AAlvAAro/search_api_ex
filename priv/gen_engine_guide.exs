# Regenerates guides/engines.md from the compiled catalog. Run by `mix docs`.
engines = SearchApi.Engine.list()

rows =
  Enum.map_join(engines, "\n", fn e ->
    required =
      case SearchApi.Engine.required_params(e) do
        [] -> "—"
        params -> Enum.map_join(params, ", ", &"`#{&1.name}`")
      end

    "| [`:#{e.id}`](#{e.docs_url}) | #{e.name} | #{required} | #{length(e.params)} |"
  end)

body = """
# Engines

All #{length(engines)} SearchApi engines, as compiled into this library. Every row
links to the official documentation, which is the reference for what each
parameter means and what the response looks like — this library passes both
through unchanged.

Anything here is also available at runtime, which is usually more useful than
reading a table:

    SearchApi.Engine.search("hotel")
    SearchApi.Engine.fetch!(:google_hotels).params
    SearchApi.Engine.json_schema(:google_hotels)

| Engine | Name | Required parameters | Total parameters |
| ------ | ---- | ------------------- | ---------------- |
#{rows}

*Generated from `priv/engines.json` by `priv/gen_engine_guide.exs`.*
"""

File.mkdir_p!("guides")
File.write!("guides/engines.md", body)
IO.puts("Wrote guides/engines.md (#{length(engines)} engines)")
