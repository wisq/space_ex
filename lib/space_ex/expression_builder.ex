defmodule SpaceEx.ExpressionBuilder do
  alias SpaceEx.ExpressionBuilder.Syntax

  defmacro __using__([]) do
    quote do
      require SpaceEx.ProcedureCall
    end
  end

  defmacro build(conn, opts \\ [], do: expr) do
    module = Keyword.get(opts, :module, SpaceEx.KRPC.Expression)

    walk(expr, %{conn: conn, module: module})
  end

  defp walk({:|>, _, [a, b]}, opts), do: pipeline(a, b, opts)
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

  defp walk({fn_name, _, args} = ast, opts) when is_atom(fn_name) do
    try do
      apply(Syntax, fn_name, args).(opts)
    rescue
      UndefinedFunctionError ->
        raise "Don't know how to build expression: #{Macro.to_string(ast)}"
    end
  end

  defp walk(str, opts) when is_bitstring(str), do: constant(:string, str, opts)

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

  defp pipeline(a, {b, b_ctx, b_args}, opts) do
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
end
