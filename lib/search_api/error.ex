defmodule SearchApi.Error do
  @moduledoc """
  The error returned by every failing `SearchApi` call.

  One struct for every failure mode, so callers can match on `:reason` and
  always have something printable in `:message`. `SearchApi.Error` implements
  the `Exception` behaviour, so it can be raised (`SearchApi.search!/3` does)
  as well as returned.

  ## Reasons

    * `:missing_api_key` — no key in the call, the application config, or
      `SEARCHAPI_API_KEY`.
    * `:unknown_engine` — the engine id is not in `SearchApi.Engine.ids/0`.
      `:context` holds the id.
    * `:http_error` — SearchApi answered with a non-2xx status. `:status` and
      `:body` hold the response.
    * `:transport_error` — the request never completed (DNS, TLS, timeout).
      `:context` holds the underlying exception.

  Only `:unknown_engine` is decided locally. Parameter problems come back as
  `:http_error`, because SearchApi validates parameters itself, describes them
  better than a scraped catalog can, and does not charge for a rejected
  request.
  """

  @type reason :: :missing_api_key | :unknown_engine | :http_error | :transport_error

  @type t :: %__MODULE__{
          reason: reason(),
          message: String.t(),
          status: pos_integer() | nil,
          body: term(),
          context: term()
        }

  defexception [:reason, :message, :status, :body, :context]

  @doc false
  def new(reason, message, fields \\ []) do
    struct!(%__MODULE__{reason: reason, message: message}, fields)
  end
end
