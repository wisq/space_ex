# This is a VERY LITERAL translation of the example LaunchIntoOrbit.py script
# included in the kRPC source tree.
#
# You should NOT try to write SpaceEx code this way.  It's utterly grotesque,
# but it's included as a first step / proof of concept, to show that
# imperative kRPC scripts can be translated literally into SpaceEx scripts.
# Better versions will follow.
#
# There have been some syntax improvements since this script was originally
# ported, some of which should allow the code to be cleaned up somewhat, but
# that cleanup is still pending.  I'll do a cleanup pass once we've reached a
# stable v1.0.0 API.
#
# This script should be used with the included "launch_into_orbit.craft" craft,
# due to the hardcoded fuel checks and stage numbers.

defmodule LaunchIntoOrbit do
  require SpaceEx.Stream
  # ... but don't try to `alias SpaceEx.Stream`,
  # because we also use Elixir's `Stream` module.

  alias SpaceEx.SpaceCenter
  alias SpaceEx.SpaceCenter.{
    Vessel, Control, AutoPilot,
    Flight, Resources, Orbit,
    CelestialBody, Node,
  }

  @turn_start_altitude 250
  @turn_end_altitude 45_000
  @target_altitude 150_000
  @atmosphere_height 70_500

  def launch(conn) do
    vessel    = SpaceCenter.active_vessel(conn)
    autopilot = Vessel.auto_pilot(conn, vessel)
    control   = Vessel.control(conn, vessel)
    surf_ref  = Vessel.surface_reference_frame(conn, vessel)
    flight    = Vessel.flight(conn, vessel, surf_ref)
    orbit     = Vessel.orbit(conn, vessel)

    # Set up streams for telemetry
    {_, fn_ut} = SpaceCenter.ut(conn) |> SpaceEx.Stream.stream_fn
    {_, fn_altitude} =
      Flight.mean_altitude(conn, flight)
      |> SpaceEx.Stream.stream_fn
    {_, fn_apoapsis} =
      Orbit.apoapsis_altitude(conn, orbit)
      |> SpaceEx.Stream.stream_fn

    stage_2_resources = Vessel.resources_in_decouple_stage(
      conn, vessel, 2, false)
    {_, fn_srb_fuel} =
      Resources.amount(conn, stage_2_resources, "SolidFuel")
      |> SpaceEx.Stream.stream_fn

    # Pre-launch setup
    Control.set_sas(conn, control, false)
    Control.set_rcs(conn, control, false)
    Control.set_throttle(conn, control, 1.0)

    # Countdown...
    IO.puts("3...")
    Process.sleep(1_000)
    IO.puts("2...")
    Process.sleep(1_000)
    IO.puts("1...")
    Process.sleep(1_000)
    IO.puts("Launch!")

    # Activate the first stage
    Control.activate_next_stage(conn, control)
    AutoPilot.engage(conn, autopilot)
    AutoPilot.target_pitch_and_heading(conn, autopilot, 90, 90)

    # Upon return, we should be at 90% of apoapsis altitude.
    ascent_loop(
      conn, autopilot, control,
      fn_altitude, fn_srb_fuel, fn_apoapsis
    )

    # Disable engines when target apoapsis is reached
    Control.set_throttle(conn, control, 0.25)
    wait_until(fn ->
      fn_apoapsis.() >= @target_altitude
    end)

    IO.puts("Target apoapsis reached")
    Control.set_throttle(conn, control, 0.0)

    # Wait until out of atmosphere
    IO.puts("Coasting out of atmosphere")
    wait_until(fn ->
      fn_altitude.() >= @atmosphere_height
    end)

    # Plan circularization burn (using vis-viva equation)
    IO.puts("Planning circularization burn")
    kerbin = Orbit.body(conn, orbit)
    mu = CelestialBody.gravitational_parameter(conn, kerbin)
    # Note: You can't use fn_apoapsis.() here,
    # because we need the apo from the _centre_ of Kerbin.
    r  = Orbit.apoapsis(conn, orbit)
    a1 = Orbit.semi_major_axis(conn, orbit)
    a2 = r
    v1 = :math.sqrt(mu*((2.0/r)-(1.0/a1)))
    v2 = :math.sqrt(mu*((2.0/r)-(1.0/a2)))
    delta_v = v2 - v1
    time_to_apo = Orbit.time_to_apoapsis(conn, orbit)
    node_ut = fn_ut.() + time_to_apo
    # `node` is an Elixir builtin, but it's not a reserved word, so.
    node = Control.add_node(conn, control, node_ut, delta_v, 0, 0)

    # Calculate burn time (using rocket equation)
    f = Vessel.available_thrust(conn, vessel)
    isp = Vessel.specific_impulse(conn, vessel)
    isp = isp * 9.82
    m0 = Vessel.mass(conn, vessel)
    m1 = m0 / :math.exp(delta_v/isp)
    flow_rate = f / isp
    burn_time = (m0 - m1) / flow_rate

    # Orientate ship
    IO.puts("Orientating ship for circularization burn")
    node_frame = Node.reference_frame(conn, node)
    AutoPilot.set_reference_frame(conn, autopilot, node_frame)
    AutoPilot.set_target_direction(conn, autopilot, {0, 1, 0})
    AutoPilot.engage(conn, autopilot)
    AutoPilot.wait(conn, autopilot)

    # Wait until burn
    IO.puts("Waiting until circularization burn")
    burn_ut = node_ut - (burn_time/2.0)
    lead_time = 5
    SpaceCenter.warp_to(conn, burn_ut - lead_time, 1000, 1000)

    # Execute burn
    IO.puts("Ready to execute burn")
    {_, fn_time_to_apoapsis} =
      Orbit.time_to_apoapsis(conn, orbit)
      |> SpaceEx.Stream.stream_fn

    wait_until(fn ->
      fn_time_to_apoapsis.() - (burn_time / 2.0) <= 0.0
    end)

    IO.puts("Executing burn")
    Control.set_throttle(conn, control, 1.0)
    round((burn_time - 0.2) * 1000) |> Process.sleep

    IO.puts("Fine tuning")
    Control.set_throttle(conn, control, 0.05)

    {_, fn_remaining_delta_v} =
      Node.remaining_delta_v(conn, node)
      |> SpaceEx.Stream.stream_fn

    wait_until(fn ->
      fn_remaining_delta_v.() <= 0.2
    end)

    Control.set_throttle(conn, control, 0.0)
    Node.remove(conn, node)

    IO.puts("Launch complete")
  end

  def ascent_loop(
    conn, autopilot, control,
    fn_altitude, fn_srb_fuel, fn_apoapsis,
    turn_angle \\ 0, srbs_separated \\ false
  ) do
    altitude = fn_altitude.()

    # Gravity turn
    turn_angle =
      if altitude > @turn_start_altitude && altitude < @turn_end_altitude do
        frac = ((altitude - @turn_start_altitude) /
                (@turn_end_altitude - @turn_start_altitude))
        new_turn_angle = frac * 90.0

        if abs(new_turn_angle - turn_angle) > 0.5 do
          AutoPilot.target_pitch_and_heading(
            conn, autopilot, 90 - new_turn_angle, 90)
          new_turn_angle
        end
      end || turn_angle

    # Separate SRBs when finished
    srbs_separated =
      if !srbs_separated && fn_srb_fuel.() < 0.1 do
        Control.activate_next_stage(conn, control)
        IO.puts("SRBs separated")
        true
      else
        srbs_separated
      end


    # Decrease throttle when approaching target apoapsis
    if fn_apoapsis.() > @target_altitude*0.9 do
      IO.puts("Approaching target apoapsis")
      # return to main sequence
    else
      ascent_loop(
        conn, autopilot, control,
        fn_altitude, fn_srb_fuel, fn_apoapsis,
        turn_angle, srbs_separated
      )
    end
  end

  # Basically an imperative 'until' loop.
  def wait_until(func) do
    Stream.cycle([:ok])
    |> Enum.find(fn _ -> func.() end)
  end
end

conn = SpaceEx.Connection.connect!(name: "Launch into orbit", host: "192.168.68.6")

try do
  LaunchIntoOrbit.launch(conn)
after
  # If the script dies, the ship will just keep doing whatever it's doing, but
  # without any control or autopilot guidance.  Pausing on completion, but
  # especially on error, makes it clear when a human should take over.
  SpaceEx.KRPC.set_paused(conn, true)
end
