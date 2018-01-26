defmodule SpaceEx.ExpressionBuilder.Syntax do
  require SpaceEx.ExpressionBuilder.Macros
  import SpaceEx.ExpressionBuilder.Macros

  def_two_args(a == b, :equal)
  def_two_args(a != b, :not_equal)
  def_two_args(a >= b, :greater_than_or_equal)
  def_two_args(a <= b, :less_than_or_equal)
  def_two_args(a < b, :less_than)
  def_two_args(a > b, :greater_than)

  def_constant(:string, [
    ~S'You can also just use string literals, e.g. `... == "a string"` or `... == "an #{interpolated_string}"`.',
    "Note that any code inside interpolated strings will not be processed by the ExpressionBuilder; rather, it will be immediately converted to its string form at the time of building."
  ])

  def_constant(:double)
  def_constant(:float)
  def_constant(:int)

  def_one_arg(to_int(value), :to_int)
  def_one_arg(to_float(value), :to_float)
  def_one_arg(to_double(value), :to_double)

  def_two_args(a && b, :and)
  def_two_args(a || b, :or)
  def_two_args(xor(a, b), :exclusive_or)
  def_one_arg(!value, :not)

  def_two_args(a + b, :add)
  def_two_args(a - b, :subtract)
  def_two_args(a * b, :multiply)
  def_two_args(rem(a, b), :modulo)
  def_two_args(a / b, :divide)
  def_two_args(power(a, b), :power)

  def_two_args(a <<< b, :left_shift)
  def_two_args(a >>> b, :right_shift)
end
