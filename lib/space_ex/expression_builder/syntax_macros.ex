defmodule SpaceEx.ExpressionBuilder.SyntaxMacros do
  @moduledoc false

  defmacro def_constant(name, extra_doc \\ nil) do
    quote do
      function = "constant_#{unquote(name)}"
      @doc SpaceEx.ExpressionBuilder.SyntaxMacros.make_doc(function, 3, unquote(extra_doc))
      def unquote(name)(value) do
        fn opts ->
          SpaceEx.ExpressionBuilder.constant(unquote(name), value, opts)
        end
      end
    end
  end

  defmacro def_two_args({_name, _, [a, b]} = prototype, function, extra_doc \\ nil) do
    quote do
      @doc SpaceEx.ExpressionBuilder.SyntaxMacros.make_doc(
             unquote(function),
             3,
             unquote(extra_doc)
           )
      def unquote(prototype) do
        fn opts ->
          SpaceEx.ExpressionBuilder.two_args(unquote(function), unquote(a), unquote(b), opts)
        end
      end
    end
  end

  defmacro def_one_arg({_name, _, [a]} = prototype, function, extra_doc \\ nil) do
    quote do
      @doc SpaceEx.ExpressionBuilder.SyntaxMacros.make_doc(
             unquote(function),
             2,
             unquote(extra_doc)
           )
      def unquote(prototype) do
        fn opts ->
          SpaceEx.ExpressionBuilder.one_arg(unquote(function), unquote(a), opts)
        end
      end
    end
  end

  def make_doc(name, arity, extra) do
    ["Builds a `SpaceEx.KRPC.Expression.#{name}/#{arity}` expression.", extra]
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
  end
end
