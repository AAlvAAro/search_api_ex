# Every request in the test suite is served by a Req.Test stub instead of the
# network. Individual tests install their own handler with Req.Test.stub/2.
Application.put_env(:search_api_ex, :req_options, plug: {Req.Test, SearchApi})
Application.put_env(:search_api_ex, :api_key, "test-key")

ExUnit.start()
