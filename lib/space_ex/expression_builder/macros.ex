defmodule SpaceEx.ExpressionBuilder.Macros do
  @moduledoc false

  defmacro def_constant(name, extra_doc \\ nil) do
    quote do
      doc =
        [
          "Builds a `SpaceEx.KRPC.Expression.constant_#{unquote(name)}/2` expression.",
          unquote(extra_doc)
        ]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)
        |> Enum.join("\n\n")

      @doc doc
      def unquote(name)(value) do
        fn opts ->
          SpaceEx.ExpressionBuilder.constant(unquote(name), value, opts)
        end
      end
    end
  end

  defmacro def_two_args({_name, _, [a, b]} = prototype, function) do
    quote do
      @doc "Builds a `SpaceEx.KRPC.Expression.#{unquote(function)}/3` expression."
      def unquote(prototype) do
        fn opts ->
          SpaceEx.ExpressionBuilder.two_args(unquote(function), unquote(a), unquote(b), opts)
        end
      end
    end
  end

  defmacro def_one_arg({_name, _, [a]} = prototype, function) do
    quote do
      @doc "Builds a `SpaceEx.KRPC.Expression.#{unquote(function)}/2` expression."
      def unquote(prototype) do
        fn opts ->
          SpaceEx.ExpressionBuilder.one_arg(unquote(function), unquote(a), opts)
        end
      end
    end
  end
end
