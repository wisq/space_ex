defmodule SpaceEx.ExpressionBuilderTest do
  use ExUnit.Case, async: true
  alias SpaceEx.Test.MockExpression

  use SpaceEx.ExpressionBuilder
  alias SpaceEx.{ExpressionBuilder, ProcedureCall, ObjectReference}

  alias SpaceEx.SpaceCenter
  alias SpaceEx.SpaceCenter.{Vessel, Orbit, Flight, Resources, CelestialBody}

  setup_all do
    MockExpression.Seen.start()
    on_exit(&MockExpression.Assertions.assert_all_functions_used/0)
  end

  test "MockExpression includes all Expression functions" do
    assert MockExpression.Assertions.functions_in(SpaceEx.KRPC.Expression) ==
             MockExpression.Assertions.functions_in(MockExpression)
  end

  test "build simple expression #1" do
    conn = :dummy_conn

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        SpaceCenter.ut(conn) > double(123.456)
      end

    assert {:greater_than, ^conn, left, right} = expr
    assert {:call, ^conn, proc} = left
    assert {:constant_double, ^conn, 123.456} = right
    assert %ProcedureCall{procedure: "get_UT"} = proc
  end

  test "build simple expression #2" do
    conn = :dummy_conn
    resources = %ObjectReference{conn: conn, id: <<123>>, class: "Resources"}

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        Resources.amount(resources, "SolidFuel") < float(0.1)
      end

    assert {:less_than, ^conn, left, right} = expr
    assert {:call, ^conn, proc} = left
    assert {:constant_float, ^conn, 0.1} = right

    assert %ProcedureCall{
             procedure: "Resources_Amount",
             args: [<<123>>, <<_, "SolidFuel">>]
           } = proc
  end

  test "build simple expression #3" do
    conn = :dummy_conn
    vessel = %ObjectReference{conn: conn, id: <<42>>, class: "Vessel"}

    # Dunno why you'd do this, but ¯\_(ツ)_/¯
    # I'm sure there must be some use for string constants.
    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        Vessel.name(vessel) != "Heart of Gold"
      end

    assert {:not_equal, ^conn, left, right} = expr
    assert {:call, ^conn, %ProcedureCall{}} = left
    assert {:constant_string, ^conn, "Heart of Gold"} = right
  end

  test "build boolean expression" do
    conn = :dummy_conn
    orbit = %ObjectReference{conn: conn, id: <<99>>, class: "Orbit"}

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        Orbit.apoapsis(orbit) >= double(1_000_000) && Orbit.eccentricity(orbit) <= double(0.1)
      end

    assert {:and, ^conn, left, right} = expr
    assert {:greater_than_or_equal, ^conn, left1, left2} = left
    assert {:less_than_or_equal, ^conn, right1, right2} = right

    assert {:call, ^conn, %ProcedureCall{}} = left1
    assert {:call, ^conn, %ProcedureCall{}} = right1

    assert {:constant_double, ^conn, 1_000_000} = left2
    assert {:constant_double, ^conn, 0.1} = right2
  end

  test "build equivalent boolean expressions with `!`, `or`, and `xor`" do
    conn = :dummy_conn
    orbit = %ObjectReference{conn: conn, id: <<99>>, class: "Orbit"}

    # Orbit is NOT between 100km and 110km, expressed with `!`.
    expr1 =
      ExpressionBuilder.build conn, module: MockExpression do
        !(Orbit.apoapsis(orbit) >= double(100_000) && Orbit.apoapsis(orbit) <= double(110_000))
      end

    assert {:not, ^conn, inner_and} = expr1
    assert {:and, ^conn, above_100km, below_110km} = inner_and
    assert {:greater_than_or_equal, ^conn, apoapsis, km100} = above_100km
    assert {:less_than_or_equal, ^conn, ^apoapsis, km110} = below_110km

    assert {:constant_double, ^conn, 100_000} = km100
    assert {:constant_double, ^conn, 110_000} = km110

    # Same, but expressed with `||`.
    expr2 =
      ExpressionBuilder.build conn, module: MockExpression do
        Orbit.apoapsis(orbit) < double(100_000) || Orbit.apoapsis(orbit) > double(110_000)
      end

    assert {:or, ^conn, below_100km, above_110km} = expr2
    assert {:less_than, ^conn, ^apoapsis, ^km100} = below_100km
    assert {:greater_than, ^conn, ^apoapsis, ^km110} = above_110km

    # Same, but expressed with `xor`.
    # Yes, technically this is no different than `||` in this case, but we need an `xor` test.
    expr2 =
      ExpressionBuilder.build conn, module: MockExpression do
        xor(
          Orbit.apoapsis(orbit) < double(100_000),
          Orbit.apoapsis(orbit) > double(110_000)
        )
      end

    assert {:exclusive_or, ^conn, ^below_100km, ^above_110km} = expr2
  end

  test "build type-converting expression" do
    conn = :dummy_conn

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        to_int(SpaceCenter.ut(conn)) > int(123)
      end

    assert {:greater_than, ^conn, left, right} = expr
    assert {:to_int, ^conn, call} = left
    assert {:constant_int, ^conn, 123} = right
    assert {:call, ^conn, %ProcedureCall{}} = call
  end

  test "build pipelining expression" do
    conn = :dummy_conn

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        int(123) |> to_double |> to_float |> to_int |> rem(int(999)) == int(123)
      end

    assert {:equal, ^conn, left, int_123} = expr
    assert {:modulo, ^conn, nested_123, int_999} = left
    assert {:to_int, ^conn, {:to_float, ^conn, {:to_double, ^conn, ^int_123}}} = nested_123

    assert {:constant_int, ^conn, 123} = int_123
    assert {:constant_int, ^conn, 999} = int_999
  end

  test "build mathematical expression #1" do
    conn = :dummy_conn

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        rem(to_int(SpaceCenter.ut(conn)), int(3600)) == int(0)
      end

    assert {:equal, ^conn, left, right} = expr
    assert {:modulo, ^conn, mod_left, mod_right} = left
    assert {:constant_int, ^conn, 0} = right

    assert {:to_int, ^conn, call} = mod_left
    assert {:constant_int, ^conn, 3600} = mod_right

    assert {:call, ^conn, %ProcedureCall{}} = call
  end

  test "build mathematical expression #2" do
    conn = :dummy_conn
    flight = %ObjectReference{conn: conn, id: <<99>>, class: "Flight"}

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        Flight.speed(flight) / Flight.terminal_velocity(flight) < double(0.5)
      end

    assert {:less_than, ^conn, left, right} = expr
    assert {:divide, ^conn, div_left, div_right} = left
    assert {:constant_double, ^conn, 0.5} = right

    assert {:call, ^conn, %ProcedureCall{}} = div_left
    assert {:call, ^conn, %ProcedureCall{}} = div_right
  end

  test "build mathematical expression #3" do
    conn = :dummy_conn
    orbit = %ObjectReference{conn: conn, id: <<101>>, class: "Orbit"}
    body = %ObjectReference{conn: conn, id: <<102>>, class: "CelestialBody"}

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        Orbit.periapsis_altitude(orbit) * double(2) >=
          CelestialBody.atmosphere_depth(body) + double(500)
      end

    assert {:greater_than_or_equal, ^conn, mul, add} = expr
    assert {:multiply, ^conn, _mul_left, mul_right} = mul
    assert {:add, ^conn, _add_left, add_right} = add
    assert {:constant_double, ^conn, 2} = mul_right
    assert {:constant_double, ^conn, 500} = add_right
  end

  test "build mathematical expression #4" do
    conn = :dummy_conn

    # If I find a real use for `power`, I'll replace this. :)
    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        power(int(2), int(10)) == power(int(32), int(2))
      end

    assert {:equal, ^conn, left, right} = expr
    assert {:power, ^conn, int_2, int_10} = left
    assert {:power, ^conn, int_32, ^int_2} = right

    assert {:constant_int, ^conn, 2} = int_2
    assert {:constant_int, ^conn, 10} = int_10
    assert {:constant_int, ^conn, 32} = int_32
  end

  test "build mathematical expression with correct order of operations" do
    conn = :dummy_conn

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        int(5) + int(10) * (int(55) - int(25))
      end

    assert {:add, ^conn, int_5, multiply} = expr
    assert {:multiply, ^conn, int_10, subtract} = multiply
    assert {:subtract, ^conn, int_55, int_25} = subtract

    assert {:constant_int, ^conn, 5} = int_5
    assert {:constant_int, ^conn, 10} = int_10
    assert {:constant_int, ^conn, 25} = int_25
    assert {:constant_int, ^conn, 55} = int_55
  end

  test "build bit-shifting expression" do
    conn = :dummy_conn

    expr =
      ExpressionBuilder.build conn, module: MockExpression do
        int(1) <<< int(3) == int(32) >>> int(2)
      end

    assert {:equal, ^conn, left, right} = expr
    assert {:left_shift, ^conn, int_1, int_3} = left
    assert {:right_shift, ^conn, int_32, int_2} = right

    assert {:constant_int, ^conn, 1} = int_1
    assert {:constant_int, ^conn, 2} = int_2
    assert {:constant_int, ^conn, 3} = int_3
    assert {:constant_int, ^conn, 32} = int_32
  end

  test "raises helpful error when raw numbers are used" do
    conn = :dummy_conn

    try_value = fn value ->
      quote do
        require ExpressionBuilder

        ExpressionBuilder.build conn, module: MockExpression do
          SpaceCenter.ut(unquote(conn)) > unquote(value)
        end
      end
      |> Code.eval_quoted()

      assert "Expected error, got none"
    end

    try do
      try_value.(123.456)
    rescue
      err ->
        # Should not mention `int(x)` for floats.
        refute err.message =~ "int(123.456)"
        assert err.message =~ "float(123.456)"
        assert err.message =~ "double(123.456)"
    end

    try do
      try_value.(123)
    rescue
      err ->
        assert err.message =~ "int(123)"
        assert err.message =~ "float(123.0)"
        assert err.message =~ "double(123.0)"
    end
  end
end
