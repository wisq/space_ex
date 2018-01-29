# This is a VERY LITERAL translation of the example LaunchIntoOrbit.py script
# included in the kRPC source tree.
#
# You should NOT try to write SpaceEx code this way.  It's pretty gross, but
# it's included as a first step / proof of concept, to show that imperative
# kRPC scripts can be translated literally into SpaceEx scripts.  See the later
# numbered files in this directory for progressively improved scripts.
#
# This script should be used with the included "LaunchIntoOrbit.craft" ship,
# due to the hardcoded fuel checks and stage numbers.

# Get some common modules like arg parsing, `Loop`, etc.
Path.expand("../common.ex", __DIR__)
|> Code.load_file()

defmodule LaunchIntoOrbit do
  require Loop
  import Loop

  require SpaceEx.Stream
  # Can still refer to Elixir's Stream as Elixir.Stream.
  alias SpaceEx.{SpaceCenter, Stream}

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

  def launch(conn) do
    vessel = SpaceCenter.active_vessel(conn)
    orbit = Vessel.orbit(vessel)

    # Set up streams for telemetry
    {_, ut} =
      SpaceCenter.ut(conn)
      |> Stream.stream()
      |> Stream.with_get_fn()

    {_, altitude} =
      Vessel.flight(vessel)
      |> Flight.mean_altitude()
      |> Stream.stream()
      |> Stream.with_get_fn()

    {_, apoapsis} =
      Orbit.apoapsis_altitude(orbit)
      |> Stream.stream()
      |> Stream.with_get_fn()

    {_, srb_fuel} =
      Vessel.resources_in_decouple_stage(vessel, 2, cumulative: false)
      |> Resources.amount("SolidFuel")
      |> Stream.stream()
      |> Stream.with_get_fn()

    # Pre-launch setup
    control = Vessel.control(vessel)
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
    autopilot = Vessel.auto_pilot(vessel)
    AutoPilot.engage(autopilot)
    AutoPilot.target_pitch_and_heading(autopilot, 90, 90)

    # Main ascent loop
    while_state {false, 0}, true do
      {srbs_separated, turn_angle} = state

      # Pitch-over maneuver, or "gravity turn" (not really).
      turn_angle =
        if altitude.() > @turn_start_altitude && altitude.() < @turn_end_altitude do
          frac =
            (altitude.() - @turn_start_altitude) / (@turn_end_altitude - @turn_start_altitude)

          new_turn_angle = frac * 90.0

          if abs(new_turn_angle - turn_angle) > 0.5 do
            AutoPilot.target_pitch_and_heading(autopilot, 90 - new_turn_angle, 90)
            new_turn_angle
          end
        end || turn_angle

      srbs_separated =
        srbs_separated ||
          if srb_fuel.() < 0.1 do
            Control.activate_next_stage(control)
            IO.puts("SRBs separated")
            true
          end

      # Decrease throttle when approaching target apoapsis
      if apoapsis.() > @target_altitude * 0.9 do
        IO.puts("Approaching target apoapsis")
        break()
      end

      {srbs_separated, turn_angle}
    end

    # Disable engines when target apoapsis is reached
    Control.set_throttle(control, 0.25)
    while(apoapsis.() < @target_altitude, do: :wait)
    IO.puts("Target apoapsis reached")
    Control.set_throttle(control, 0.0)

    # Wait until out of atmosphere
    IO.puts("Coasting out of atmosphere")
    while(altitude.() < 70500, do: :wait)

    # Plan circularization burn (using vis-viva equation)
    IO.puts("Planning circularization burn")
    mu = Orbit.body(orbit) |> CelestialBody.gravitational_parameter()
    r = Orbit.apoapsis(orbit)
    a1 = Orbit.semi_major_axis(orbit)
    a2 = r
    v1 = :math.sqrt(mu * (2.0 / r - 1.0 / a1))
    v2 = :math.sqrt(mu * (2.0 / r - 1.0 / a2))
    delta_v = v2 - v1
    # `node` is an Elixir builtin, but it's not a reserved word, so.
    node = Control.add_node(control, ut.() + Orbit.time_to_apoapsis(orbit), prograde: delta_v)

    # Calculate burn time (using rocket equation)
    f = Vessel.available_thrust(vessel)
    isp = Vessel.specific_impulse(vessel) * 9.82
    m0 = Vessel.mass(vessel)
    m1 = m0 / :math.exp(delta_v / isp)
    flow_rate = f / isp
    burn_time = (m0 - m1) / flow_rate

    # Orientate ship
    IO.puts("Orientating ship for circularization burn")
    AutoPilot.set_reference_frame(autopilot, Node.reference_frame(node))
    AutoPilot.set_target_direction(autopilot, {0, 1, 0})
    # Note that AutoPilot.wait sometimes returns immediately, without waiting.
    # It's an old bug in kRPC, not a bug in this code.
    AutoPilot.wait(autopilot)

    # Wait until burn
    IO.puts("Waiting until circularization burn")
    burn_ut = ut.() + Orbit.time_to_apoapsis(orbit) - burn_time / 2.0
    lead_time = 5
    SpaceCenter.warp_to(conn, burn_ut - lead_time)

    # Execute burn
    IO.puts("Ready to execute burn")

    {_, time_to_apoapsis} =
      Orbit.time_to_apoapsis(orbit) |> SpaceEx.Stream.stream() |> SpaceEx.Stream.with_get_fn()

    while(time_to_apoapsis.() - burn_time / 2.0 > 0, do: :wait)
    IO.puts("Executing burn")
    Control.set_throttle(control, 1.0)
    # Remember that Process.sleep() expects integer milliseconds, not a float.
    round((burn_time - 0.1) * 1000) |> Process.sleep()
    IO.puts("Fine tuning")
    Control.set_throttle(control, 0.05)

    # The original script does `remaining_burn_vector` in *the node's*
    # reference frame, but this means the reference frame follows the node's
    # vector.  I honestly don't know how this has ever worked.
    #
    # Since the amount of error between the ship's vector and the node's vector
    # increases as the remaining delta-v approaches zero, there always tends to
    # be some residual delta-v, but in the wrong direction.  The ship just
    # spins and burns, trying to align itself with a vector that it can never
    # quite reach, until it runs out of fuel.  I'm not even sure it's
    # technically possible for the Y value to go negative.
    #
    # Doing the calculation in the ship's orbital vector (the default) tends
    # to work way better.  Basically, we keep burning until the node is no
    # longer pointing in the prograde direction.
    {_, remaining_burn} =
      Node.remaining_burn_vector(node)
      |> Stream.stream()
      |> Stream.with_get_fn()

    while(remaining_burn.() |> elem(1) > 0.0, do: :wait)
    Control.set_throttle(control, 0.0)
    Node.remove(node)

    IO.puts("Launch complete")
  end
end

Example.run(__ENV__, &LaunchIntoOrbit.launch/1, "Launch into orbit")
