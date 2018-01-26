defmodule SpaceEx.ExpressionBuilder do
  defmacro __using__([]) do
    quote do
      require SpaceEx.ProcedureCall
    end
  end

  defmacro build(conn, opts \\ [], do: expr) do
    module = Keyword.get(opts, :module, SpaceEx.KRPC.Expression)

    walk(expr, %{conn: conn, module: module})
  end

  defmodule Syntax do
    alias SpaceEx.ExpressionBuilder, as: EB

    def a == b, do: fn opts -> EB.two_args(:equal, a, b, opts) end
    def a != b, do: fn opts -> EB.two_args(:not_equal, a, b, opts) end
    def a >= b, do: fn opts -> EB.two_args(:greater_than_or_equal, a, b, opts) end
    def a <= b, do: fn opts -> EB.two_args(:less_than_or_equal, a, b, opts) end
    def a < b, do: fn opts -> EB.two_args(:less_than, a, b, opts) end
    def a > b, do: fn opts -> EB.two_args(:greater_than, a, b, opts) end

    def double(value), do: fn opts -> EB.constant(:double, value, opts) end
    def string(value), do: fn opts -> EB.constant(:string, value, opts) end
    def float(value), do: fn opts -> EB.constant(:float, value, opts) end
    def int(value), do: fn opts -> EB.constant(:int, value, opts) end

    def to_int(value), do: fn opts -> EB.one_arg(:to_int, value, opts) end
    def to_float(value), do: fn opts -> EB.one_arg(:to_float, value, opts) end
    def to_double(value), do: fn opts -> EB.one_arg(:to_double, value, opts) end

    def a && b, do: fn opts -> EB.two_args(:and, a, b, opts) end
    def a || b, do: fn opts -> EB.two_args(:or, a, b, opts) end
    def xor(a, b), do: fn opts -> EB.two_args(:exclusive_or, a, b, opts) end
    def !value, do: fn opts -> EB.one_arg(:not, value, opts) end

    def a + b, do: fn opts -> EB.two_args(:add, a, b, opts) end
    def a - b, do: fn opts -> EB.two_args(:subtract, a, b, opts) end
    def a * b, do: fn opts -> EB.two_args(:multiply, a, b, opts) end
    def rem(a, b), do: fn opts -> EB.two_args(:modulo, a, b, opts) end
    def a / b, do: fn opts -> EB.two_args(:divide, a, b, opts) end
    def power(a, b), do: fn opts -> EB.two_args(:power, a, b, opts) end

    def a <<< b, do: fn opts -> EB.two_args(:left_shift, a, b, opts) end
    def a >>> b, do: fn opts -> EB.two_args(:right_shift, a, b, opts) end
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

  defp walk({fn_name, _, args}, opts) when is_atom(fn_name) do
    apply(Syntax, fn_name, args).(opts)
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

  def one_arg(fn_name, arg, opts) do
    arg = walk(arg, opts)

    quote location: :keep do
      unquote(opts.module).unquote(fn_name)(unquote(opts.conn), unquote(arg))
    end
  end

  def two_args(fn_name, a, b, opts) do
    a = walk(a, opts)
    b = walk(b, opts)

    quote location: :keep do
      unquote(opts.module).unquote(fn_name)(unquote(opts.conn), unquote(a), unquote(b))
    end
  end

  def constant(type, value, opts) do
    fn_name = :"constant_#{type}"

    quote location: :keep do
      unquote(opts.module).unquote(fn_name)(unquote(opts.conn), unquote(value))
    end
  end

  defp pipeline(a, {b, b_ctx, b_args}, opts) do
    b_args = [a | b_args || []]
    b = {b, b_ctx, b_args}
    walk(b, opts)
  end
end
