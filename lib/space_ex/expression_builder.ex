defmodule SpaceEx.ExpressionBuilder do
  alias SpaceEx.ExpressionBuilder.Syntax

  @moduledoc """
  Much simpler syntax for `SpaceEx.KRPC.Expression`.

  This can be used to streamline the creation of events.  For example, the rather unwieldy syntax

  ```elixir
  # Wait until under 1,000m altitude:
  srf_altitude = Flight.surface_altitude(flight) |> ProcedureCall.create()

  expr =
    Expression.less_than(
      conn,
      Expression.call(conn, srf_altitude),
      Expression.constant_double(conn, 1_000)
    )

  Event.create(conn, expr) |> Event.wait()
  ```

  Can be replaced with

  ```
  use ExpressionBuilder

  expr =
    ExpressionBuilder.build conn do
      Flight.surface_altitude(flight) < double(1_000)
    end
  ```

  For a full list of supported syntax forms, see `SpaceEx.ExpressionBuilder.Syntax`.

  It's recommended that you include this module via `use`, so that it can issue
  `require` statements for other modules it uses macros from.
  """

  defmacro __using__([]) do
    quote location: :keep do
      require SpaceEx.ProcedureCall
    end
  end

  @doc """
  Builds a `SpaceEx.KRPC.Expression` based on the supplied block of code.

  Syntax elements are sourced from `SpaceEx.ExpressionBuilder.Syntax`.  See
  that module for details.

  `opts` may be omitted.  If present, additional options are possible:

  * `opts[:as_string]` — If `true`, the code to generate an expression will be returned as a string.  This may be useful for debugging issues with your expressions.
  """
  defmacro build(conn, opts \\ [], block) do
    # Options may show up in either `opts` or `block`, depending on usage:
    #
    # `build(conn, a: b) do x end` -> opts = [a: b], block = [do: x]
    # `build conn, a: b, do: x` -> opts = [], block = [a: b, do: x]
    #
    # So just merge them and treat them as a single unit.
    opts = Keyword.merge(opts, block)
    block = Keyword.fetch!(opts, :do)

    # Undocumented, used in test suite:
    module = Keyword.get(opts, :module, SpaceEx.KRPC.Expression)
    type_module = Keyword.get(opts, :type_module, SpaceEx.KRPC.Type)

    ast = walk(block, %{conn: conn, module: module, type_module: type_module})

    if opts[:as_string] do
      Macro.to_string(ast)
    else
      ast
    end
  end

  defp walk({:__block__, _, [inner]}, opts), do: walk(inner, opts)

  defp walk({{:., _, _} = function, _, args}, opts) do
    quote location: :keep do
      unquote(opts.module).call(
        unquote(opts.conn),
        unquote(function)(unquote_splicing(args))
        |> SpaceEx.ProcedureCall.create()
      )
    end
  end

  defp walk({:<<>>, _, _} = str, _opts) do
    str = Macro.to_string(str)
    raise "Bare strings cannot be used in expressions; please use string(#{str})"
  end

  defp walk({fn_name, _, args} = ast, opts) when is_atom(fn_name) do
    try do
      apply(Syntax, fn_name, args).(opts)
    rescue
      UndefinedFunctionError ->
        raise "Don't know how to build expression: #{Macro.to_string(ast)}"
    end
  end

  defp walk(str, _opts) when is_bitstring(str) do
    raise "Bare strings cannot be used in expressions; please use string(#{inspect(str)})"
  end

  defp walk(n, _opts) when is_number(n) do
    fns =
      if is_integer(n) do
        "int(#{n}), float(#{n}.0), or double(#{n}.0)"
      else
        "float(#{n}) or double(#{n})"
      end

    raise "Bare numbers cannot be used in expressions; please use #{fns}"
  end

  defp walk(unknown, _opts) do
    # IO.inspect(unknown, width: 0)
    raise "Don't know how to build expression: #{Macro.to_string(unknown)}"
  end

  def pipeline(a, {b, b_ctx, b_args}, opts) do
    b_args = [a | b_args || []]
    b = {b, b_ctx, b_args}
    walk(b, opts)
  end

  @doc false
  def one_arg(fn_name, arg, opts) do
    arg = walk(arg, opts)

    quote location: :keep do
      unquote(opts.module).unquote(fn_name)(unquote(opts.conn), unquote(arg))
    end
  end

  @doc false
  def two_args(fn_name, a, b, opts) do
    a = walk(a, opts)
    b = walk(b, opts)

    quote location: :keep do
      unquote(opts.module).unquote(fn_name)(unquote(opts.conn), unquote(a), unquote(b))
    end
  end

  @doc false
  def constant(type, value, opts) do
    fn_name = :"constant_#{type}"

    quote location: :keep do
      unquote(opts.module).unquote(fn_name)(unquote(opts.conn), unquote(value))
    end
  end

  @doc false
  def cast(value, type, opts) do
    value = walk(value, opts)

    quote location: :keep do
      unquote(opts.module).cast(
        unquote(opts.conn),
        unquote(value),
        unquote(opts.type_module).unquote(type)(unquote(opts.conn))
      )
    end
  end
end
