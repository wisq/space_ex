# This is a VERY LITERAL translation of the example LaunchIntoOrbit.py script
# included in the kRPC source tree.
#
# You should NOT try to write SpaceEx code this way.  It's utterly grotesque,
# but it's included as a first step / proof of concept, to show that
# imperative kRPC scripts can be translated literally into SpaceEx scripts.
# Better versions will follow.
#
# This script should be used with the included "launch_into_orbit.craft" craft,
# due to the hardcoded fuel checks and stage numbers.

defmodule LaunchIntoOrbit do
  require SpaceEx.Stream
  # ... but don't try to `alias SpaceEx.Stream`,
  # because we also use Elixir's `Stream` module.

  alias SpaceEx.SpaceCenter

  alias SpaceEx.SpaceCenter.{
    Vessel,
    Control,
    AutoPilot,
    Flight,
    Resources,
    Orbit,
    CelestialBody,
    Node
  }

  # Begin pitching over at 250m altitude.
  @turn_start_altitude 250
  # We should be fully pitched over and aimed at the horizon at 45km.
  @turn_end_altitude 45_000
  # Aim for a circular orbit at 150km altitude.
  @target_altitude 150_000
  # The atmosphere ends at 70km, but give it 500m margin.
  @atmosphere_height 70_500

  def launch(conn) do
    vessel = SpaceCenter.active_vessel(conn)
    autopilot = Vessel.auto_pilot(vessel)
    control = Vessel.control(vessel)
    flight = Vessel.flight(vessel)
    orbit = Vessel.orbit(vessel)

    # Set up streams for telemetry
    {_, fn_ut} = SpaceCenter.ut(conn) |> SpaceEx.Stream.stream_fn()

    {_, fn_altitude} =
      Flight.mean_altitude(flight)
      |> SpaceEx.Stream.stream_fn()

    {_, fn_apoapsis} =
      Orbit.apoapsis_altitude(orbit)
      |> SpaceEx.Stream.stream_fn()

    {_, fn_srb_fuel} =
      Vessel.resources_in_decouple_stage(vessel, 2, cumulative: false)
      |> Resources.amount("SolidFuel")
      |> SpaceEx.Stream.stream_fn()

    # Pre-launch setup
    Control.set_sas(control, false)
    Control.set_rcs(control, false)
    Control.set_throttle(control, 1.0)

    # Countdown...
    IO.puts("3...")
    Process.sleep(1_000)
    IO.puts("2...")
    Process.sleep(1_000)
    IO.puts("1...")
    Process.sleep(1_000)
    IO.puts("Launch!")

    # Activate the first stage
    Control.activate_next_stage(control)
    AutoPilot.engage(autopilot)
    AutoPilot.target_pitch_and_heading(autopilot, 90, 90)

    # Upon return, we should be at 90% of apoapsis altitude.
    ascent_loop(
      conn,
      autopilot,
      control,
      fn_altitude,
      fn_srb_fuel,
      fn_apoapsis
    )

    # Disable engines when target apoapsis is reached
    Control.set_throttle(control, 0.25)

    wait_until(fn ->
      fn_apoapsis.() >= @target_altitude
    end)

    IO.puts("Target apoapsis reached")
    Control.set_throttle(control, 0.0)

    # Wait until out of atmosphere
    IO.puts("Coasting out of atmosphere")

    wait_until(fn ->
      fn_altitude.() >= @atmosphere_height
    end)

    # Plan circularization burn (using vis-viva equation)
    IO.puts("Planning circularization burn")
    kerbin = Orbit.body(orbit)
    mu = CelestialBody.gravitational_parameter(kerbin)
    # Note: You can't use fn_apoapsis.() here,
    # because we need the apo from the _centre_ of Kerbin.
    r = Orbit.apoapsis(orbit)
    a1 = Orbit.semi_major_axis(orbit)
    a2 = r
    v1 = :math.sqrt(mu * (2.0 / r - 1.0 / a1))
    v2 = :math.sqrt(mu * (2.0 / r - 1.0 / a2))
    delta_v = v2 - v1
    time_to_apo = Orbit.time_to_apoapsis(orbit)
    node_ut = fn_ut.() + time_to_apo
    # `node` is an Elixir builtin, but it's not a reserved word, so.
    node = Control.add_node(control, node_ut, prograde: delta_v)

    # Calculate burn time (using rocket equation)
    f = Vessel.available_thrust(vessel)
    isp = Vessel.specific_impulse(vessel)
    isp = isp * 9.82
    m0 = Vessel.mass(vessel)
    m1 = m0 / :math.exp(delta_v / isp)
    flow_rate = f / isp
    burn_time = (m0 - m1) / flow_rate

    # Orientate ship
    IO.puts("Orientating ship for circularization burn")
    node_frame = Node.reference_frame(node)
    AutoPilot.set_reference_frame(autopilot, node_frame)
    AutoPilot.set_target_direction(autopilot, {0, 1, 0})
    AutoPilot.engage(autopilot)

    # The original script uses `AutoPilot.wait` here,
    # but I don't generally recommend using that function.
    # On some occasions, it returns immediately, without
    # waiting at all.  Other times, it can't quite get
    # the orientation right, and waits forever.
    # Better to just monitor the error directly.
    {_, error_fn} = AutoPilot.error(autopilot) |> SpaceEx.Stream.stream_fn()

    Stream.repeatedly(fn ->
      # The sleep is important; it makes the time math work, below.
      Process.sleep(100)
      error_fn.()
    end)
    |> Enum.reduce_while([], fn err, errors ->
      errors = [err | errors]

      if Enum.count(errors) < 30 do
        # Not enough samples; we want 3 seconds worth.
        {:cont, errors}
      else
        last_3_secs = Enum.take(errors, 30)

        if Enum.all?(last_3_secs, &(abs(&1) < 0.5)) do
          # We've maintained under half a degree of error
          # for the past three seconds.  Any remaining
          # error can be corrected during the lead time.
          {:halt, :ok}
        else
          {:cont, last_3_secs}
        end
      end
    end)

    # Wait until burn
    IO.puts("Waiting until circularization burn")
    burn_ut = node_ut - burn_time / 2.0
    lead_time = 5
    SpaceCenter.warp_to(conn, burn_ut - lead_time)

    # Execute burn
    IO.puts("Ready to execute burn")

    {_, fn_time_to_apoapsis} =
      Orbit.time_to_apoapsis(orbit)
      |> SpaceEx.Stream.stream_fn()

    wait_until(fn ->
      fn_time_to_apoapsis.() - burn_time / 2.0 <= 0.0
    end)

    IO.puts("Executing burn")
    Control.set_throttle(control, 1.0)
    # Remember that Process.sleep() expects integer milliseconds, not a float.
    round((burn_time - 0.2) * 1000) |> Process.sleep()

    IO.puts("Fine tuning")
    Control.set_throttle(control, 0.05)

    {_, fn_remaining_delta_v} =
      Node.remaining_delta_v(node)
      |> SpaceEx.Stream.stream_fn()

    wait_until(fn ->
      fn_remaining_delta_v.() <= 0.2
    end)

    Control.set_throttle(control, 0.0)
    Node.remove(node)

    IO.puts("Launch complete")
  end

  def ascent_loop(
        conn,
        autopilot,
        control,
        fn_altitude,
        fn_srb_fuel,
        fn_apoapsis,
        turn_angle \\ 0,
        srbs_separated \\ false
      ) do
    altitude = fn_altitude.()

    # Pitch-over maneuver, or "gravity turn" (not really).
    turn_angle =
      if altitude > @turn_start_altitude && altitude < @turn_end_altitude do
        frac = (altitude - @turn_start_altitude) / (@turn_end_altitude - @turn_start_altitude)
        new_turn_angle = frac * 90.0

        if abs(new_turn_angle - turn_angle) > 0.5 do
          AutoPilot.target_pitch_and_heading(autopilot, 90 - new_turn_angle, 90)
          new_turn_angle
        end
      end || turn_angle

    # Separate SRBs when finished
    srbs_separated =
      if !srbs_separated && fn_srb_fuel.() < 0.1 do
        Control.activate_next_stage(control)
        IO.puts("SRBs separated")
        true
      else
        srbs_separated
      end

    # Decrease throttle when approaching target apoapsis
    if fn_apoapsis.() > @target_altitude * 0.9 do
      IO.puts("Approaching target apoapsis")
      # return to main sequence
    else
      ascent_loop(
        conn,
        autopilot,
        control,
        fn_altitude,
        fn_srb_fuel,
        fn_apoapsis,
        turn_angle,
        srbs_separated
      )
    end
  end

  # Basically an imperative 'until' loop.
  def wait_until(func) do
    Stream.cycle([:ok])
    |> Enum.find(fn _ -> func.() end)
  end
end

conn = SpaceEx.Connection.connect!(name: "Launch into orbit")

try do
  LaunchIntoOrbit.launch(conn)
  Process.sleep(1_000)
after
  # If the script dies, the ship will just keep doing whatever it's doing,
  # but without any control or autopilot guidance.  Pausing on completion,
  # but especially on error, makes it clear when a human should take over.
  SpaceEx.KRPC.set_paused(conn, true)
end
