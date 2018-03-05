defmodule SpaceEx.Test.MockExpression do
  # WARNING: This module is NOT ASYNC-SAFE.
  #
  # Currently, only ExpressionBuilderTest uses this.  If multiple modules use
  # it, we'll need to either mark them as `async: false`, or update
  # MockExpression.Seen to use something better than itself as the process
  # name.
  #
  # Frankly, though, I can't imagine any use for this outside of that test.
  # Maybe if that test got split into multiple files, but that's about it.

  @moduledoc false

  defmodule Type do
    def bool(_conn), do: :mock_bool_type
    def double(_conn), do: :mock_double_type
    def float(_conn), do: :mock_float_type
    def int(_conn), do: :mock_int_type
    def string(_conn), do: :mock_string_type
  end

  @one_arg [
    # Procedure calls:
    :call,
    # Constants:
    :constant_int,
    :constant_float,
    :constant_double,
    :constant_string,
    # Conversions:
    :to_int,
    :to_float,
    :to_double,
    # Boolean logic:
    :not
  ]

  @two_args [
    # Comparisons:
    :equal,
    :not_equal,
    :greater_than,
    :greater_than_or_equal,
    :less_than,
    :less_than_or_equal,
    # Boolean logic:
    :and,
    :or,
    :exclusive_or,
    # Math:
    :add,
    :subtract,
    :multiply,
    :divide,
    :modulo,
    :power,
    # Bit shifting:
    :left_shift,
    :right_shift
  ]

  Enum.each(@one_arg, fn fn_name ->
    def unquote(fn_name)(conn, value) do
      GenServer.cast(__MODULE__.Seen, {:called, unquote(fn_name), 2})
      {unquote(fn_name), conn, value}
    end
  end)

  Enum.each(@two_args, fn fn_name ->
    def unquote(fn_name)(conn, left, right) do
      GenServer.cast(__MODULE__.Seen, {:called, unquote(fn_name), 3})
      {unquote(fn_name), conn, left, right}
    end
  end)

  defmodule Seen do
    use GenServer

    def start do
      GenServer.start(__MODULE__, nil, name: __MODULE__)
    end

    def shutdown do
      seen = GenServer.call(__MODULE__, :seen)
      GenServer.stop(__MODULE__)
      {:ok, seen}
    end

    @impl true
    def init(nil) do
      {:ok, MapSet.new()}
    end

    @impl true
    def handle_cast({:called, name, arity}, seen) do
      seen = MapSet.put(seen, {name, arity})
      {:noreply, seen}
    end

    @impl true
    def handle_call(:seen, _from, seen) do
      {:reply, seen, seen}
    end
  end

  defmodule Assertions do
    alias SpaceEx.Test.MockExpression

    def assert_all_functions_used do
      {:ok, seen} = MockExpression.Seen.shutdown()

      missing =
        MockExpression.__info__(:functions)
        |> Enum.reject(&(&1 in seen))
        |> Enum.map(fn {name, arity} -> "#{name}/#{arity}" end)

      unless Enum.empty?(missing) do
        lines = [
          "These Expression functions are not covered by any test:"
          | missing |> Enum.sort()
        ]

        lines
        |> Enum.join("\n  ")
        |> raise
      end
    end

    def functions_in(module) do
      module.__info__(:functions)
      |> Enum.reject(fn {name, _arity} ->
        Atom.to_string(name)
        |> String.starts_with?("rpc_")
      end)
    end
  end
end
