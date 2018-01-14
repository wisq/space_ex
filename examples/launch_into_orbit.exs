# This is a VERY LITERAL translation of the example LaunchIntoOrbit.py script
# included in the kRPC source tree.
#
# You should NOT try to write SpaceEx code this way.  It's utterly grotesque,
# but it's included as a first step / proof of concept, to show that
# imperative kRPC scripts can be translated literally into SpaceEx scripts.
# Better versions will follow.
#
# Note also that the current syntax (as of writing this) leaves a lot to be
# desired.  The constant need to check `:ok` codes is tiresome and prevents
# some nicer nested code.  I'm considering whether to auto-generate ...
# 
#   * "bang" versions of all methods that enforce the :ok code;
#   * structs for vessel, flight, etc. that include the conn, to allow piping;
#   * versions of functions that use keyword arguments instead of positional.
#
# The lack of streams is also not ideal -- they can be simulated somewhat with
# anonymous functions, but obviously with reduced performance.
#
# This script should be used with the stock "Kerbal 1" craft, due to the
# hardcoded fuel checks and stage numbers.

defmodule LaunchIntoOrbit do
  alias SpaceEx.SpaceCenter
  alias SpaceEx.SpaceCenter.{
    Vessel, Control, AutoPilot,
    Flight, Resources, Orbit,
    CelestialBody, Node,
  }

  @turn_start_altitude 250
  @turn_end_altitude 55_000
  @target_altitude 150_000

  def launch(conn) do
    {:ok, vessel}    = SpaceCenter.get_active_vessel(conn)
    {:ok, autopilot} = Vessel.get_auto_pilot(conn, vessel)
    {:ok, control}   = Vessel.get_control(conn, vessel)
    {:ok, surf_ref}  = Vessel.get_surface_reference_frame(conn, vessel)
    {:ok, flight}    = Vessel.flight(conn, vessel, surf_ref)
    #{:ok, resources} = Vessel.get_resources(conn, vessel)
    {:ok, orbit}     = Vessel.get_orbit(conn, vessel)

    # We don't have streams currently, but
    # anonymous functions can mimic them for now.
    fn_ut = fn ->
      {:ok, value} = SpaceCenter.get_ut(conn)
      value
    end
    fn_altitude = fn ->
      {:ok, value} = Flight.get_mean_altitude(conn, flight)
      value
    end
    fn_apoapsis = fn ->
      {:ok, value} = Orbit.get_apoapsis_altitude(conn, orbit)
      value
    end

    {:ok, stage_4_resources} = Vessel.resources_in_decouple_stage(conn, vessel, 4, false)
    {:ok, stage_3_resources} = Vessel.resources_in_decouple_stage(conn, vessel, 3, false)

    fn_srb_fuel = fn ->
      {:ok, value} = Resources.amount(conn, stage_4_resources, "SolidFuel")
      value
    end
    fn_liquid_fuel = fn ->
      {:ok, value} = Resources.amount(conn, stage_3_resources, "LiquidFuel")
      value
    end

    # Pre-launch setup
    {:ok, _} = Control.set_sas(conn, control, false)
    {:ok, _} = Control.set_rcs(conn, control, false)
    {:ok, _} = Control.set_throttle(conn, control, 1.0)

    # Countdown...
    IO.puts("3...")
    Process.sleep(1_000)
    IO.puts("2...")
    Process.sleep(1_000)
    IO.puts("1...")
    Process.sleep(1_000)
    IO.puts("Launch!")

    # Activate the first stage
    {:ok, _} = Control.activate_next_stage(conn, control)
    {:ok, _} = AutoPilot.engage(conn, autopilot)
    {:ok, _} = AutoPilot.target_pitch_and_heading(conn, autopilot, 90, 90)

    # Upon return, we should be at 90% of apoapsis altitude.
    ascent_loop(
      conn, autopilot, control, fn_altitude,
      fn_srb_fuel, fn_liquid_fuel, fn_apoapsis
    )

    # Disable engines when target apoapsis is reached
    {:ok, _} = Control.set_throttle(conn, control, 0.25)
    # This is effectively the functional equivalent of a 'while' loop. :)
    Stream.cycle([:ok]) |> Enum.find(fn _ ->
      fn_apoapsis.() >= @target_altitude
    end)

    IO.puts("Target apoapsis reached")
    {:ok, _} = Control.set_throttle(conn, control, 0.0)

    # Wait until out of atmosphere
    IO.puts("Coasting out of atmosphere")
    Stream.cycle([:ok]) |> Enum.find(fn _ ->
      fn_altitude.() >= 70_500
    end)

    # Plan circularization burn (using vis-viva equation)
    IO.puts("Planning circularization burn")
    {:ok, kerbin} = Orbit.get_body(conn, orbit)
    {:ok, mu} = CelestialBody.get_gravitational_parameter(conn, kerbin)
    # Note: You can't use fn_apoapsis.() here,
    # because we need the apo from the _centre_ of Kerbin.
    {:ok, r}  = Orbit.get_apoapsis(conn, orbit)
    {:ok, a1} = Orbit.get_semi_major_axis(conn, orbit)
    a2 = r
    v1 = :math.sqrt(mu*((2.0/r)-(1.0/a1)))
    v2 = :math.sqrt(mu*((2.0/r)-(1.0/a2)))
    delta_v = v2 - v1
    {:ok, time_to_apo} = Orbit.get_time_to_apoapsis(conn, orbit)
    node_ut = fn_ut.() + time_to_apo
    {:ok, maneuver_node} = Control.add_node(
      conn, control, node_ut, delta_v, 0, 0)

    # Calculate burn time (using rocket equation)
    {:ok, f} = Vessel.get_available_thrust(conn, vessel)
    {:ok, isp} = Vessel.get_specific_impulse(conn, vessel)
    isp = isp * 9.82
    {:ok, m0} = Vessel.get_mass(conn, vessel)
    m1 = m0 / :math.exp(delta_v/isp)
    flow_rate = f / isp
    burn_time = (m0 - m1) / flow_rate

    # Orientate ship
    IO.puts("Orientating ship for circularization burn")
    {:ok, node_frame} = Node.get_reference_frame(conn, maneuver_node)
    {:ok, _} = AutoPilot.set_reference_frame(conn, autopilot, node_frame)
    {:ok, _} = AutoPilot.set_target_direction(conn, autopilot, {0, 1, 0})
    {:ok, _} = AutoPilot.engage(conn, autopilot)
    {:ok, _} = AutoPilot.wait(conn, autopilot)

    # Wait until burn
    IO.puts("Waiting until circularization burn")
    burn_ut = node_ut - (burn_time/2.0)
    lead_time = 5
    {:ok, _} = SpaceCenter.warp_to(conn, burn_ut - lead_time, 1000, 1000)

    # Execute burn
    IO.puts("Ready to execute burn")
    Stream.cycle([:ok]) |> Enum.find(fn _ ->
      fn_ut.() >= burn_ut
    end)

    IO.puts("Executing burn")
    {:ok, _} = Control.set_throttle(conn, control, 1.0)
    round((burn_time - 0.2) * 1000) |> Process.sleep

    IO.puts("Fine tuning")
    {:ok, _} = Control.set_throttle(conn, control, 0.05)

    Stream.cycle([:ok]) |> Enum.find(fn _ ->
      {:ok, dv} = Node.get_remaining_delta_v(conn, maneuver_node)
      dv <= 0.2
    end)

    {:ok, _} = Control.set_throttle(conn, control, 0.0)
    {:ok, _} = Node.remove(conn, maneuver_node)

    IO.puts("Launch complete")
  end

  def ascent_loop(conn, autopilot, control, fn_altitude,
                  fn_srb_fuel, fn_liquid_fuel, fn_apoapsis,
                  turn_angle \\ 0, current_stage \\ 5) do
    altitude = fn_altitude.()

    # Gravity turn
    turn_angle =
      if altitude > @turn_start_altitude && altitude < @turn_end_altitude do
        frac = ((altitude - @turn_start_altitude) /
                (@turn_end_altitude - @turn_start_altitude))
        new_turn_angle = frac * 90.0

        if abs(new_turn_angle - turn_angle) > 0.5 do
          cond do
            turn_angle == 0 -> IO.puts("Beginning gravity turn ...")
            new_turn_angle >= 89.5 -> IO.puts("Gravity turn complete.")
            true -> :ok
          end
          {:ok, _} = AutoPilot.target_pitch_and_heading(conn, autopilot, 90 - new_turn_angle, 90)
          new_turn_angle
        end
      end || turn_angle

    # Separate SRBs when finished
    current_stage =
      case current_stage do
        5 ->
          if fn_srb_fuel.() < 0.1 do
            {:ok, _} = Control.activate_next_stage(conn, control)
            IO.puts("SRBs separated")
            4
          end
        4 ->
          if fn_liquid_fuel.() < 0.1 do
            {:ok, _} = Control.activate_next_stage(conn, control)
            IO.puts("Bottom liquid fuel separated")
            Process.sleep(1_000)
            {:ok, _} = Control.activate_next_stage(conn, control)
            IO.puts("Next engine ignited")
            2
          end
        _ -> nil
      end || current_stage

    # Decrease throttle when approaching target apoapsis
    if fn_apoapsis.() > @target_altitude*0.9 do
      IO.puts("Approaching target apoapsis")
      # return to main sequence
    else
      ascent_loop(conn, autopilot, control, fn_altitude,
                  fn_srb_fuel, fn_liquid_fuel, fn_apoapsis,
                  turn_angle, current_stage)
    end
  end
end

conn = SpaceEx.Connection.connect!(name: "Launch into orbit")

SpaceEx.KRPC.set_paused(conn, false)
LaunchIntoOrbit.launch(conn)
SpaceEx.KRPC.set_paused(conn, true)
