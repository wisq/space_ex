defmodule SpaceEx.Service.SpaceCenterTest do
  use ExUnit.Case, async: true

  alias SpaceEx.Test.MockConnection

  alias SpaceEx.SpaceCenter
  alias SpaceEx.Protobufs.Argument
  alias SpaceEx.ObjectReference

  setup do
    {:ok, MockConnection.start()}
  end

  # Tests:
  #   * object reference return value
  test "SpaceCenter.get_active_vessel/1", state do
    # ID of remote Vessel object.
    MockConnection.add_result_value(<<123>>, state.conn)

    assert %ObjectReference{} = vessel = SpaceCenter.active_vessel(state.conn)
    assert vessel.id == <<123>>
    assert vessel.conn == state.conn

    assert [call] = MockConnection.dump_calls(state.conn)
    assert call.service == "SpaceCenter"
    assert call.procedure == "get_ActiveVessel"
    assert call.arguments == []
  end

  # Tests:
  #   * extracting `conn` from object reference
  #   * pipelining calls
  #   * numeric return values
  test "SpaceCenter.Vessel.max_thrust/1 via SpaceCenter.get_active_vessel/1", state do
    # ID of remote Vessel object.
    MockConnection.add_result_value(<<111>>, state.conn)
    # 456.789 in type FLOAT, but floats are imprecise.
    MockConnection.add_result_value(<<254, 100, 228, 67>>, state.conn)

    assert max_thrust =
             SpaceCenter.active_vessel(state.conn)
             |> SpaceCenter.Vessel.max_thrust()

    assert_in_delta max_thrust, 456.789, 0.001

    assert [_active_vessel, call] = MockConnection.dump_calls(state.conn)
    assert call.service == "SpaceCenter"
    assert call.procedure == "Vessel_get_MaxThrust"
    assert [%Argument{position: 0, value: <<111>>}] = call.arguments
  end

  # Tests:
  #   * supplying optional arguments
  #   * omitting optional arguments (and using defaults)
  test "SpaceCenter.warp_to/3", state do
    MockConnection.add_result_value(<<>>, state.conn)

    assert SpaceCenter.warp_to(state.conn, 12345.6789, max_physics_rate: 2) == :ok

    assert [call] = MockConnection.dump_calls(state.conn)
    assert call.service == "SpaceCenter"
    assert call.procedure == "WarpTo"
    assert [ut, max_rails, max_physics] = call.arguments

    # 12345.6789 as DOUBLE
    assert %Argument{position: 0, value: <<161, 248, 49, 230, 214, 28, 200, 64>>} = ut
    # 100,000 as FLOAT
    assert %Argument{position: 1, value: <<0, 80, 195, 71>>} = max_rails
    # 2 as FLOAT
    assert %Argument{position: 2, value: <<0, 0, 0, 64>>} = max_physics
  end

  # Tests:
  #   * omitting all optional arguments altogether
  test "SpaceCenter.Vessel.flight/1 via SpaceCenter.get_active_vessel/1", state do
    # ID of remote Vessel object.
    MockConnection.add_result_value(<<86>>, state.conn)
    # ID of remote Flight object.
    MockConnection.add_result_value(<<99>>, state.conn)

    assert %ObjectReference{id: <<99>>} =
             SpaceCenter.active_vessel(state.conn)
             |> SpaceCenter.Vessel.flight()

    assert [_active_vessel, call] = MockConnection.dump_calls(state.conn)
    assert call.service == "SpaceCenter"
    assert call.procedure == "Vessel_Flight"
    assert [vessel, ref_frame] = call.arguments

    # ID of remote Vessel object.
    assert %Argument{position: 0, value: <<86>>} = vessel
    # Default value: null ID.
    assert %Argument{position: 1, value: <<0>>} = ref_frame
  end

  # Tests:
  #   * supplying multiple reference objects
  #   * supplying reference objects as optional arguments
  test "SpaceCenter.Vessel.flight/2 via several", state do
    # ID of remote Vessel object.
    MockConnection.add_result_value(<<101>>, state.conn)
    # ID of remote ReferenceFrame object.
    MockConnection.add_result_value(<<102>>, state.conn)
    # ID of remote Flight object.
    MockConnection.add_result_value(<<103>>, state.conn)

    assert %ObjectReference{id: <<101>>} = vessel = SpaceCenter.active_vessel(state.conn)
    assert %ObjectReference{id: <<102>>} = ref_frame = SpaceCenter.Vessel.reference_frame(vessel)

    assert %ObjectReference{id: <<103>>} =
             SpaceCenter.Vessel.flight(vessel, reference_frame: ref_frame)

    assert [_active_vessel, ref_call, flight_call] = MockConnection.dump_calls(state.conn)

    assert ref_call.service == "SpaceCenter"
    assert ref_call.procedure == "Vessel_get_ReferenceFrame"
    assert [%Argument{position: 0, value: <<101>>}] = ref_call.arguments

    assert flight_call.service == "SpaceCenter"
    assert flight_call.procedure == "Vessel_Flight"
    assert [vessel_arg, ref_frame_arg] = flight_call.arguments

    # ID of remote Vessel object.
    assert %Argument{position: 0, value: <<101>>} = vessel_arg
    # ID of remote ReferenceFrame object.
    assert %Argument{position: 1, value: <<102>>} = ref_frame_arg
  end

  # Tests:
  #   * enumeration as an argument
  test "SpaceCenter.Control.set_speed_mode/2 via several", state do
    # ID of remote Vessel object.
    MockConnection.add_result_value(<<11>>, state.conn)
    # ID of remote Control object.
    MockConnection.add_result_value(<<12>>, state.conn)

    assert %ObjectReference{id: <<11>>} = vessel = SpaceCenter.active_vessel(state.conn)
    assert %ObjectReference{id: <<12>>} = control = SpaceCenter.Vessel.control(vessel)
    assert [_active_vessel, _control] = MockConnection.dump_calls(state.conn)

    MockConnection.add_result_value(<<>>, state.conn)
    SpaceCenter.Control.set_speed_mode(control, :orbit)

    MockConnection.add_result_value(<<>>, state.conn)
    SpaceCenter.Control.set_speed_mode(control, :target)

    assert [orbit, target] = MockConnection.dump_calls(state.conn)

    assert orbit.service == "SpaceCenter"
    assert orbit.procedure == "Control_set_SpeedMode"
    assert [control_arg, orbit_arg] = orbit.arguments

    assert target.service == "SpaceCenter"
    assert target.procedure == "Control_set_SpeedMode"
    assert [^control_arg, target_arg] = target.arguments

    assert %Argument{position: 0, value: <<12>>} = control_arg
    assert %Argument{position: 1, value: <<0>>} = orbit_arg
    assert %Argument{position: 1, value: <<4>>} = target_arg
  end
end
