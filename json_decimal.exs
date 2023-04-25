Mix.install(
  [
    :tesla,
    :jason,
    :decimal
  ],
  # necessary only in this script
  consolidate_protocols: false
)

# The bad API
defmodule BadApiAdapter do
  @behaviour Tesla.Adapter

  def call(req, _opts) do
    IO.puts("request body: #{req.body}")

    {:ok,
     %{
       req
       | headers: [{"content-type", "application/json"}],
         body: """
         {"price": 1.01}
         """
     }}
  end
end

defmodule GoodClient1 do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://example.com"
  plug Tesla.Middleware.JSON

  adapter BadApiAdapter

  def price() do
    get("/price")
  end
end

{:ok, %{body: %{"price" => price}}} = GoodClient1.price()
dbg(price)
# => 1.01
# Seems ok, but...
dbg(price * 3)
# => 3.0300000000000002

# Step 1. Configure Jason to use decimals instead of floats

defmodule GoodClient2 do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://example.com"

  # Configure Jason to parse floats as decimals
  plug Tesla.Middleware.JSON, engine: Jason, engine_opts: [floats: :decimals]

  adapter BadApiAdapter

  def price() do
    get("/price")
  end
end

{:ok, %{body: %{"price" => price}}} = GoodClient2.price()
dbg(price)
# => #Decimal<1.01>
dbg(Decimal.mult(price, 3))
# => #Decimal<3.03>

# Step 2. What about request body?

defmodule GoodClient3 do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://example.com"
  plug Tesla.Middleware.JSON, engine: Jason, engine_opts: [floats: :decimals]

  adapter BadApiAdapter

  def bid(price) do
    post("/bid", %{price: price})
  end
end

{:ok, _env} = GoodClient3.bid(Decimal.new(price))
# request body: {"price":"1.01"}

# Since Jason already defines encode for Decimal we need to work around it.
# Let's create a custom JSON middleware that can handle Decimal for us.

defmodule FloatsAsDecimalsJSON do
  @behaviour Tesla.Middleware

  # Create a wrapper struct
  defstruct [:decimal]
  # and implement Jason Encode to output decimal as number
  defimpl Jason.Encoder do
    # output string, but without quotes
    def encode(%{decimal: decimal}, _opts), do: Decimal.to_string(decimal, :normal)
  end

  @json_opts [engine: Jason, engine_opts: [floats: :decimals]]

  def call(env, next, opts) do
    opts = Keyword.merge(env.opts, opts)

    # 1. Wrap Decimals into struct
    with {:ok, env} <- encode(env),
         # 2. Encode request body with JSON middleware
         {:ok, env} <- Tesla.Middleware.JSON.encode(env, @json_opts ++ opts),
         # 3. Perform the request
         {:ok, env} <- Tesla.run(env, next),
         # 4. Decode response body with JSON middleware
         {:ok, env} <- Tesla.Middleware.JSON.decode(env, @json_opts ++ opts) do
      {:ok, env}
    end
  end

  defp encode(%Tesla.Env{body: body} = env), do: {:ok, %{env | body: encode(body)}}
  # wrap Decimal into struct
  defp encode(%Decimal{} = decimal), do: %__MODULE__{decimal: decimal}
  # traverse rest of data to find all Decimals
  defp encode(%{} = map), do: Enum.into(map, %{}, &encode/1)
  defp encode({k, v}), do: {k, encode(v)}
  defp encode(list) when is_list(list), do: Enum.map(list, &encode/1)
  defp encode(v), do: v
end

defmodule GoodClient4 do
  use Tesla

  plug Tesla.Middleware.BaseUrl, "http://example.com"
  plug FloatsAsDecimalsJSON

  adapter BadApiAdapter

  def bid(price) do
    post("/bid", %{price: price})
  end
end

{:ok, _env} = GoodClient4.bid(Decimal.new(price))
# request body: {"price":1.01}
