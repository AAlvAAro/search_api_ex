defmodule SearchApi do
  @moduledoc """
  An Elixir client for [SearchApi](https://www.searchapi.io) — real-time SERP
  and structured web data from #{length(SearchApi.Engine.ids())} engines.

  SearchApi is one HTTP endpoint that changes behaviour based on an `engine`
  parameter, so this library is one function:

      SearchApi.search(:google, q: "elixir lang")
      SearchApi.search(:youtube_transcripts, video_id: "dQw4w9WgXcQ")
      SearchApi.search(:google_maps, q: "coffee", ll: "@40.7455,-74.0083,14z")

  Parameter names, and the shape of the JSON that comes back, are exactly the
  ones in the [SearchApi documentation](https://www.searchapi.io/docs/google).
  This library does not rename, wrap, or reshape them — see
  [What changes in Elixir](what-changes-in-elixir.html) for the short list of
  things that *are* different.

  ## Configuration

      config :search_api_ex, api_key: "YOUR_KEY"

  The key is read from, in order: the `:api_key` option on the call, the
  application environment, then the `SEARCH_API_KEY` (or `SEARCHAPI_API_KEY`)
  environment variable.
  It is sent as a `Bearer` token, never as a query parameter, so it stays out
  of logs and proxy access records.

  ## Results

  `search/3` returns `{:ok, body}` where `body` is the decoded JSON as a map
  with string keys — the response documented for that engine, untouched. Every
  response also carries `"search_metadata"` (request id, status, timing) and
  `"search_parameters"` (the parameters SearchApi actually used).

      {:ok, body} = SearchApi.search(:google, q: "elixir lang")

      for result <- body["organic_results"] do
        IO.puts("\#{result["position"]}. \#{result["title"]} — \#{result["link"]}")
      end

  Failures come back as `{:error, %SearchApi.Error{}}`, which carries a
  `:reason` you can match on. An unknown engine is caught locally; everything
  else is SearchApi's own error, passed through with its status and body.

  ## Discovering engines

  The full catalog is compiled into the library, so engines, their parameters
  and their documentation are all available at runtime:

      SearchApi.Engine.search("shopping")
      SearchApi.Engine.fetch!(:google_flights).params
      SearchApi.Engine.json_schema(:google_flights)

  `SearchApi.Engine.json_schema/1` emits a JSON Schema in the shape MCP wants
  for a tool's `inputSchema`, which is the intended way to build an MCP server
  on top of this library. See
  [Building an MCP server](building-an-mcp-server.html).
  """

  alias SearchApi.{Engine, Error}

  @base_url "https://www.searchapi.io/api/v1/search"

  @type params :: Enumerable.t()
  @type opts :: [api_key: String.t(), req_options: keyword()]

  @doc """
  Run a search.

  `engine` is an engine id — an atom or a string, see `SearchApi.Engine.ids/0`.
  `params` is a keyword list or map of that engine's parameters; keys may be
  atoms or strings. `nil` values are dropped, lists are joined with commas
  (SearchApi's convention for repeatable filters).

  ## Options

    * `:api_key` — overrides the configured key, for multi-tenant callers.
    * `:req_options` — merged into the underlying
      [`Req`](https://hexdocs.pm/req) request, for `:receive_timeout`,
      `:retry`, `:plug` and anything else Req accepts.

  ## Examples

      SearchApi.search(:google, q: "elixir lang", gl: "lt", num: 20)

      SearchApi.search(:google_scholar, %{"q" => "attention is all you need"})

      SearchApi.search(:amazon_search, [q: "keyboard"],
        api_key: tenant.search_api_key,
        req_options: [receive_timeout: 90_000]
      )

  An unknown engine is rejected without a request:

      iex> {:error, error} = SearchApi.search(:not_an_engine, q: "x")
      iex> error.reason
      :unknown_engine

  Missing or invalid *parameters* are SearchApi's call, not this library's —
  see `SearchApi.Engine.required_params/1` if you want to check first.
  """
  @spec search(atom() | String.t(), params(), opts()) :: {:ok, map()} | {:error, Error.t()}
  def search(engine, params \\ [], opts \\ []) do
    with {:ok, engine} <- fetch_engine(engine),
         {:ok, api_key} <- api_key(opts) do
      request(engine, normalize(params), api_key, opts)
    end
  end

  @doc """
  Same as `search/3`, but returns the body directly and raises
  `SearchApi.Error` on failure.

      body = SearchApi.search!(:google, q: "elixir lang")
  """
  @spec search!(atom() | String.t(), params(), opts()) :: map()
  def search!(engine, params \\ [], opts \\ []) do
    case search(engine, params, opts) do
      {:ok, body} -> body
      {:error, error} -> raise error
    end
  end

  defp fetch_engine(engine) do
    case Engine.fetch(engine) do
      {:ok, engine} ->
        {:ok, engine}

      :error ->
        {:error,
         Error.new(
           :unknown_engine,
           "unknown engine #{inspect(to_string(engine))}. " <>
             "See SearchApi.Engine.ids/0 or SearchApi.Engine.search/1.",
           context: to_string(engine)
         )}
    end
  end

  defp normalize(params) do
    params
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {to_string(k), encode_value(v)} end)
  end

  defp encode_value(v) when is_list(v), do: Enum.map_join(v, ",", &encode_value/1)
  defp encode_value(v) when is_binary(v), do: v
  defp encode_value(v), do: to_string(v)

  defp api_key(opts) do
    key =
      opts[:api_key] ||
        Application.get_env(:search_api_ex, :api_key) ||
        System.get_env("SEARCH_API_KEY") ||
        System.get_env("SEARCHAPI_API_KEY")

    if key do
      {:ok, key}
    else
      {:error,
       Error.new(
         :missing_api_key,
         "no SearchApi key. Set `config :search_api_ex, api_key: ...`, " <>
           "the SEARCH_API_KEY environment variable, or pass `api_key:`."
       )}
    end
  end

  defp request(engine, params, api_key, opts) do
    req_options =
      Application.get_env(:search_api_ex, :req_options, [])
      |> Keyword.merge(Keyword.get(opts, :req_options, []))

    [
      url: @base_url,
      params: Map.put(params, "engine", engine.id),
      auth: {:bearer, api_key},
      headers: [{"user-agent", user_agent()}]
    ]
    |> Keyword.merge(req_options)
    |> Req.new()
    |> Req.get()
    |> handle(engine)
  end

  defp handle({:ok, %Req.Response{status: status, body: body}}, _engine)
       when status in 200..299,
       do: {:ok, body}

  defp handle({:ok, %Req.Response{status: status, body: body}}, engine) do
    {:error,
     Error.new(
       :http_error,
       "SearchApi returned #{status} for engine #{engine.id}: #{detail(body)}",
       status: status,
       body: body
     )}
  end

  defp handle({:error, exception}, engine) do
    {:error,
     Error.new(
       :transport_error,
       "could not reach SearchApi for engine #{engine.id}: #{Exception.message(exception)}",
       context: exception
     )}
  end

  defp detail(%{"error" => error}) when is_binary(error), do: error
  defp detail(body), do: inspect(body)

  @version Mix.Project.config()[:version]
  defp user_agent, do: "search_api_ex/#{@version} (Elixir)"
end
