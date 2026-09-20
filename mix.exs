defmodule SearchApi.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/AAlvAAro/search_api_ex"

  def project do
    [
      app: :search_api_ex,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      name: "SearchApi",
      description:
        "Elixir client for SearchApi.io — real-time Google, YouTube, Amazon, " <>
          "Maps and 140+ other search engines, with a runtime engine catalog " <>
          "that drops straight into an MCP server.",
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.16", only: :test},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp aliases do
    [docs: ["run priv/gen_engine_guide.exs", "docs"]]
  end

  defp package do
    [
      licenses: ["MIT"],
      maintainers: ["Alvaro Delgado"],
      links: %{
        "GitHub" => @source_url,
        "SearchApi" => "https://www.searchapi.io",
        "SearchApi docs" => "https://www.searchapi.io/docs/google"
      },
      files: ~w(lib priv/engines.json priv/gen_engine_guide.exs guides mix.exs README.md
                CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      extras: [
        "README.md",
        "guides/what-changes-in-elixir.md",
        "guides/building-an-mcp-server.md",
        "guides/engines.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      groups_for_extras: [Guides: ~r/guides\//],
      groups_for_modules: [
        Client: [SearchApi],
        Catalog: [SearchApi.Engine],
        Errors: [SearchApi.Error]
      ],
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end
end
