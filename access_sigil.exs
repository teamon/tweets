defmodule AccessSigil do
  @doc """
  A sigil for building Access paths.

  Modifiers:
  - a - use atom keys instead of strings

  ## Examples

      iex> import AccessSigil

      iex> ~k[foo.bar.0.baz]
      ["foo", "bar", Access.at(0), "baz"]

      iex> ~k[foo.bar.*.baz]a
      [Access.key(:foo), Access.key(:bar), Access.all(), Access.key(:baz)]
  """
  defmacro sigil_k({:<<>>, _, [binary]}, mods) do
    binary
    |> String.split(".")
    |> Enum.map(fn
      "*" ->
        quote(do: Access.all())

      <<head::size(8)>> <> _ = num when head in ?0..?9 ->
        quote(do: Access.at(unquote(String.to_integer(num))))

      key when mods == 'a' ->
        quote(do: Access.key(unquote(String.to_existing_atom(key))))

      key ->
        key
    end)
  end
end

ExUnit.start()

defmodule AccessSigilTest do
  use ExUnit.Case

  import AccessSigil

  test "sigil_k" do
    assert ~k[foo.bar.0.baz] == ["foo", "bar", Access.at(0), "baz"]

    assert ~k[foo.bar.*.baz]a == [
             Access.key(:foo),
             Access.key(:bar),
             Access.all(),
             Access.key(:baz)
           ]
  end

  test "run" do
    data = %{
      "a" => %{
        "b" => %{
          "c" => 42,
          "d" => [
            %{"e" => 1},
            %{"e" => 2},
            %{"e" => 3},
            %{"e" => 4}
          ]
        }
      }
    }

    dbg(data)
    dbg(get_in(data, ~k[a.b.c]))
    dbg(get_in(data, ~k[a.b.d.0.e]))
    dbg(get_in(data, ~k[a.b.d.*.e]))
    dbg(update_in(data, ~k[a.b.d.*.e], &(&1 + 1)))
  end
end
