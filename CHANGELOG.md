# Changelog

All notable changes to this project are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-20

Initial release.

### Added

- `SearchApi.search/3` and `SearchApi.search!/3` against every SearchApi engine.
- `SearchApi.Engine`, a compiled-in catalog of all 151 engines and their 1146
  documented parameters, with `list/0`, `fetch/1`, `search/1` and
  `json_schema/1`.
- `SearchApi.Engine.json_schema/1`, emitting MCP-shaped `inputSchema` objects
  so the catalog can drive an MCP server directly.
- Local validation of unknown engines and missing required parameters, before
  a request is sent.
- `SearchApi.Error`, one struct for every failure mode.

[0.1.0]: https://github.com/AAlvAAro/search_api_ex/releases/tag/v0.1.0
