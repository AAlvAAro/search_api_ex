defmodule SearchApiTest do
  # async: false — these tests mutate the application env and OS env.
  use ExUnit.Case, async: false

  doctest SearchApi

  defp stub(fun), do: Req.Test.stub(SearchApi, fun)

  defp json(conn, status \\ 200, body) do
    conn |> Plug.Conn.put_status(status) |> Req.Test.json(body)
  end

  defp params(conn), do: Plug.Conn.fetch_query_params(conn).query_params

  describe "search/3 request building" do
    test "sends the engine and parameters as query params" do
      stub(fn conn ->
        assert %{"engine" => "google", "q" => "elixir lang", "gl" => "lt"} = params(conn)
        json(conn, %{"organic_results" => []})
      end)

      assert {:ok, %{"organic_results" => []}} =
               SearchApi.search(:google, q: "elixir lang", gl: "lt")
    end

    test "accepts string engine ids and map params with string keys" do
      stub(fn conn ->
        assert %{"engine" => "google", "q" => "hi"} = params(conn)
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search("google", %{"q" => "hi"})
    end

    test "stringifies non-binary values and joins lists with commas" do
      stub(fn conn ->
        assert %{"num" => "20", "page" => "2", "lang" => "en,lt"} = params(conn)
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google, q: "x", num: 20, page: 2, lang: ["en", "lt"])
    end

    test "drops nil values so optional params can be passed through unconditionally" do
      stub(fn conn ->
        refute Map.has_key?(params(conn), "location")
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google, q: "x", location: nil)
    end

    test "sends the api key as a bearer token, never as a query param" do
      stub(fn conn ->
        assert ["Bearer test-key"] = Plug.Conn.get_req_header(conn, "authorization")
        refute Map.has_key?(params(conn), "api_key")
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google, q: "x")
    end

    test ":api_key option overrides the configured key" do
      stub(fn conn ->
        assert ["Bearer per-call"] = Plug.Conn.get_req_header(conn, "authorization")
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google, [q: "x"], api_key: "per-call")
    end

    test "identifies itself with a versioned user agent" do
      stub(fn conn ->
        assert [ua] = Plug.Conn.get_req_header(conn, "user-agent")
        assert ua =~ ~r{^search_api_ex/\d+\.\d+\.\d+ \(Elixir\)$}
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google, q: "x")
    end
  end

  describe "search/3 validation" do
    test "rejects an unknown engine before making a request" do
      stub(fn _conn -> flunk("should not have made a request") end)

      assert {:error, %SearchApi.Error{reason: :unknown_engine, context: "nope"}} =
               SearchApi.search(:nope, q: "x")
    end

    test "leaves parameter validation to SearchApi, which does not charge for it" do
      stub(fn conn ->
        assert %{"engine" => "youtube_transcripts"} = params(conn)
        json(conn, 400, %{"error" => "Missing required parameter video_id."})
      end)

      assert {:error, %SearchApi.Error{reason: :http_error, status: 400} = error} =
               SearchApi.search(:youtube_transcripts, [])

      assert error.message =~ "Missing required parameter video_id."
    end

    test "sends calls whose required params are conditional, rather than pre-rejecting them" do
      # google_maps_place takes place_id OR data_id; both are documented
      # "Required", so validating locally would reject every possible call.
      stub(fn conn ->
        assert %{"place_id" => "abc"} = params(conn)
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google_maps_place, place_id: "abc")
    end

    test "reports a missing api key" do
      Application.delete_env(:search_api_ex, :api_key)
      previous = System.get_env("SEARCH_API_KEY")
      System.delete_env("SEARCH_API_KEY")
      System.delete_env("SEARCHAPI_API_KEY")

      on_exit(fn ->
        Application.put_env(:search_api_ex, :api_key, "test-key")
        if previous, do: System.put_env("SEARCH_API_KEY", previous)
      end)

      assert {:error, %SearchApi.Error{reason: :missing_api_key}} =
               SearchApi.search(:google, q: "x")
    end

    test "falls back to the SEARCH_API_KEY environment variable" do
      Application.delete_env(:search_api_ex, :api_key)
      previous = System.get_env("SEARCH_API_KEY")
      System.put_env("SEARCH_API_KEY", "from-env")

      on_exit(fn ->
        if previous,
          do: System.put_env("SEARCH_API_KEY", previous),
          else: System.delete_env("SEARCH_API_KEY")

        Application.put_env(:search_api_ex, :api_key, "test-key")
      end)

      stub(fn conn ->
        assert ["Bearer from-env"] = Plug.Conn.get_req_header(conn, "authorization")
        json(conn, %{})
      end)

      assert {:ok, _} = SearchApi.search(:google, q: "x")
    end
  end

  describe "search/3 failures" do
    test "wraps a non-2xx response, keeping the status and body" do
      stub(fn conn -> json(conn, 401, %{"error" => "Invalid API key"}) end)

      assert {:error, %SearchApi.Error{reason: :http_error} = error} =
               SearchApi.search(:google, q: "x")

      assert error.status == 401
      assert error.body == %{"error" => "Invalid API key"}
      assert error.message =~ "Invalid API key"
    end

    test "wraps a transport failure" do
      stub(fn conn -> Req.Test.transport_error(conn, :econnrefused) end)

      assert {:error, %SearchApi.Error{reason: :transport_error} = error} =
               SearchApi.search(:google, [q: "x"], req_options: [retry: false])

      assert error.message =~ "could not reach SearchApi"
    end
  end

  describe "search!/3" do
    test "returns the body directly" do
      stub(fn conn -> json(conn, %{"ok" => true}) end)
      assert SearchApi.search!(:google, q: "x") == %{"ok" => true}
    end

    test "raises the error struct" do
      assert_raise SearchApi.Error, ~r/unknown engine/, fn ->
        SearchApi.search!(:nope, q: "x")
      end
    end
  end

  describe ":req_options" do
    test "are merged into the underlying request" do
      stub(fn conn ->
        assert ["yes"] = Plug.Conn.get_req_header(conn, "x-custom")
        json(conn, %{})
      end)

      assert {:ok, _} =
               SearchApi.search(:google, [q: "x"], req_options: [headers: [{"x-custom", "yes"}]])
    end
  end
end
