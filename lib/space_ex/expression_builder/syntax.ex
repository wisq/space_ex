defmodule SpaceEx.ExpressionBuilder.Syntax do
  require SpaceEx.ExpressionBuilder.SyntaxMacros
  import SpaceEx.ExpressionBuilder.SyntaxMacros

  alias SpaceEx.ExpressionBuilder, as: EB

  @moduledoc ~S"""
  Syntax functions and special forms allowed in `SpaceEx.ExpressionBuilder` blocks.

  In order to use the expression builder, your expression must be capable of
  being parsed using only the functions in this module, plus the procedure call
  syntax (see below).

  Wherever possible, the expression builder syntax is designed to be similar to
  real Elixir code.  Infix operators (like `==/2` and `&&/2`) are used when
  available; function syntax is used when not (e.g. `xor/2`).

  ## Procedure calls

  Procedure calls are the only "special" syntax not covered by the functions in this module.

  Any expression in the form of `Module.function(args)` will be treated as a kRPC call.  Thus,

  ```
  SpaceEx.ExpressionBuilder.build conn1 do
    SpaceEx.SpaceCenter.ut(conn2)
  end
  ```

  will be turned into

  ```
  SpaceEx.KRPC.Expression.call(
    conn1,
    SpaceEx.SpaceCenter.ut(conn2) |> SpaceEx.ProcedureCall.create()
  )
  ```

  Using this automatic syntax, you can build complex expressions with relative ease:

  ```
  ExpressionBuilder.build conn do
    Orbit.periapsis_altitude(orbit) > double(150_000) && Orbit.eccentricity(orbit) < double(0.1)
  end
  ```

  This results in seven different `SpaceEx.KRPC.Expression` objects being
  created, and would normally involve a nested mess of code that is too long
  and ugly to include here.

  Note that you can include arbitrary arguments to your procedure calls, and
  even pipeline procedure calls together within the expression builder syntax,
  but only the outermost procedure call (or the rightmost, if using the `|>/2`
  operator) will be stored as part of the expression.  See the next section for
  details.

  ## Expressions are constant

  The expression builder syntax is very minimal, and it does not tolerate
  syntax outside of the functions and operators listed here. However, several
  of these *do* allow for arbitrary Elixir expressions to be nested inside them
  — for example, you could do `int(x + 10)`, `string("My name is #{inigo.name}")`, etc.

  Since expressions are used for `SpaceEx.Event` calls, and Events are
  effectively running over and over on the kRPC server, you might wonder if
  this is somehow executing arbitrary code on the server.  But what's actually
  going on is, your code is being evaluated only once — at the time you build
  the expression — and then "baked in" to the expression.

  So if you try to do something like `string("The current time is #{Time.utc_now()}")`,
  you're effectively only doing `string("The current time is 12:32:54.497540")`, and
  it's not going to be current for very long.

  The only thing that can be dynamic in an expression are the procedure calls.
  However, even here, you also need to be careful.  If you try to build an
  expression such as

  ```
  ExpressionBuilder.build conn do
    SpaceCenter.active_vessel() |> Vessel.flight() |> Flight.mean_altitude() < double(70_000)
  end
  ```

  then you might expect that it would continually monitor the altitude of the
  current vessel, and follow you if you change vessels. But this isn't what's
  happening!

  In fact, every call except the final `Flight.mean_altitude` is being executed
  immediately, when the expression is created.  A clearer version would be

  ```
  flight = SpaceCenter.active_vessel() |> Vessel.flight()

  ExpressionBuilder.build conn do
    Flight.mean_altitude(flight) < double(70_000)
  end
  ```

  since this makes it more obvious that the only dynamic call is
  `Flight.mean_altitude(flight)`, and the `flight` parameter is baked in to the
  expression and cannot change.
  """

  def_two_args(a == b, :equal)
  def_two_args(a != b, :not_equal)
  def_two_args(a >= b, :greater_than_or_equal)
  def_two_args(a <= b, :less_than_or_equal)
  def_two_args(a < b, :less_than)
  def_two_args(a > b, :greater_than)

  constant_warning =
    ~S'Remember that, although `value` will accept arbitrary Elixir code, it will be turned into a constant value when the expression is built.  See ["Expressions are constant"](#module-expressions-are-constant) in the module documentation.'

  def_constant(:string, [
    constant_warning <> "  (This includes interpolated values within the string.)"
  ])

  def_constant(:double, [
    ~S'Use this when comparing against "high precision" decimals.',
    constant_warning
  ])

  def_constant(:float, [
    ~S'Use this when comparing against "low precision" decimals.',
    constant_warning
  ])

  def_constant(:int, constant_warning)

  def_one_arg(to_int(value), :to_int)
  def_one_arg(to_float(value), :to_float)
  def_one_arg(to_double(value), :to_double)

  def_one_arg(!value, :not)
  def_two_args(a && b, :and)
  def_two_args(a || b, :or)

  def_two_args(xor(a, b), :exclusive_or, [
    "This uses a function call, since there's no Elixir equivalent."
  ])

  def_two_args(a + b, :add)
  def_two_args(a - b, :subtract)
  def_two_args(a * b, :multiply)
  def_two_args(a / b, :divide)

  def_two_args(rem(a, b), :modulo, [
    "This uses the Elixir `Kernel.rem/2` syntax, instead of `%` or `mod` like other languages."
  ])

  def_two_args(power(a, b), :power, [
    "Technically, the corresponding Elixir syntax would be `:math.power(a, b)`, but that would be detected as a procedure call, so our syntax drops the module component."
  ])

  def_two_args(a <<< b, :left_shift, ["The Elixir equivalent would be `Bitwise.<<</2`."])
  def_two_args(a >>> b, :right_shift, ["The Elixir equivalent would be `Bitwise.>>>/2`."])

  @doc """
  Pipe operator.

  Works identically to the standard Elixir syntax, except within the context of the expression builder.  Thus, `int(99) |> rem(86)` is the same as `rem(int(99), 86)`, and `SpaceCenter.ut(conn) |> to_int` is the same as `to_int(SpaceCenter.ut(conn))`.

  Note that kRPC calls can be pipelined together, but only the final call will be included in the expression.  See ["Expressions are constant"](#module-expressions-are-constant) in the module documentation.

  See `Kernel.|>/2`.
  """
  def a |> b do
    fn opts ->
      EB.pipeline(a, b, opts)
    end
  end

  @doc """
  Cast a value to a given type.

  `type` is an atom that indicates what type to cast to.  See `SpaceEx.KRPC.Type` for the list of valid types.
  """
  def cast(value, type) do
    fn opts ->
      EB.cast(value, type, opts)
    end
  end
end
