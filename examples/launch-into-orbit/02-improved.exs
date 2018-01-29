# This is a mostly-literal translation of the example LaunchIntoOrbit.py script
# included in the kRPC source tree, but with some Elixir-specific improvements.
#
# This isn't a terrible way to write SpaceEx code, but it could do with some
# improvements.  The `while` loops are considered something of an anti-pattern
# in Erlang and Elixir -- ideally, we should be event-driven by messages, not
# blocking and looping.
#
# Compared to the original, this version has dramatically reduced CPU usage,
# owing mainly to the use of `Stream.wait` instead of `Stream.get` (via
# `with_get_fn` in the original).  This ensures that we're not looping
# needlessly, processing the exact same data over and over and coming to
# conclusions that literally cannot be any different than last time.
#
# The "SRB separation" and "pitch-over" loops are now running in
# their own sub-processes.  We don't even need to monitor or wait for
# them (e.g. with `Task.await/2`), since they're not relevant to the
# main goal -- getting to 150km apoapsis and circularising there.
# This also allows us to more easily output information about each.
#
# In a few places, we're now making better use of values we
# calculated previously.  For example, there's no need to constantly
# do math about the burn time -- we already plotted exactly when it
# would be, so just use that.
#
# Finally, we're no longer doing `Process.sleep` except during the
# countdown (which is purely aesthetic).  Since Kerbal has various
# kinds of time warps -- and because kRPC network latency might play
# a role, too -- it's important not to assume that time is passing
# the same in-game as it is on the client side.
#
# Other minor improvements include autopilot error checks, more
# verbose information and a final report, etc.
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
    # Fetch relevant objects:
    vessel = SpaceCenter.active_vessel(conn)
    orbit = Vessel.orbit(vessel)
    control = Vessel.control(vessel)
    autopilot = Vessel.auto_pilot(vessel)

    # Set up streams for telemetry:
    s_ut = SpaceCenter.ut(conn) |> Stream.stream()
    s_altitude = Vessel.flight(vessel) |> Flight.mean_altitude() |> Stream.stream()
    s_apo_alti = Orbit.apoapsis_altitude(orbit) |> Stream.stream()
    # Other streams are created in the processes that use them, and are automatically cleaned up.

    # Helper function for messages:
    altitude_m = fn ->
      Stream.get(s_altitude) |> format_integer()
    end

    # Pre-launch setup:
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

    # Activate the first stage:
    Control.activate_next_stage(control)
    AutoPilot.engage(autopilot)
    AutoPilot.target_pitch_and_heading(autopilot, 90, 90)

    # Pitch-over loop:
    spawn_link(fn ->
      while(Stream.wait(s_altitude) < @turn_start_altitude, do: :wait)
      IO.puts("Beginning pitch-over at #{altitude_m.()}m ...")

      while_state 0, true do
        turn_angle = state

        # Waiting for the next value will throttle this loop
        # so it only runs once per stream cycle.
        altitude = Stream.wait(s_altitude)
        if altitude > @turn_end_altitude, do: break()

        frac = (altitude - @turn_start_altitude) / (@turn_end_altitude - @turn_start_altitude)
        new_turn_angle = frac * 90.0

        if abs(new_turn_angle - turn_angle) > 0.5 do
          AutoPilot.target_pitch_and_heading(autopilot, 90 - new_turn_angle, 90)
          new_turn_angle
        else
          turn_angle
        end
      end

      # Remove any fractional pitch -- aim directly at horizon.
      AutoPilot.target_pitch_and_heading(autopilot, 0, 90)
      IO.puts("Pitch-over complete at #{altitude_m.()}m.")
    end)

    # SRB separation loop:
    spawn_link(fn ->
      s_srb_fuel =
        Vessel.resources_in_decouple_stage(vessel, 2, cumulative: false)
        |> Resources.amount("SolidFuel")
        |> Stream.stream()

      while(Stream.wait(s_srb_fuel) > 0.1, do: :wait)

      IO.puts("SRBs separating at #{altitude_m.()}m.")
      Control.activate_next_stage(control)
    end)

    # Throttle back when nearing target apoapsis:
    while(Stream.wait(s_apo_alti) < @target_altitude * 0.9, do: :wait)
    IO.puts("Approaching target apoapsis ...")
    Control.set_throttle(control, 0.25)

    # Disable engines when target apoapsis is reached:
    while(Stream.wait(s_apo_alti) < @target_altitude, do: :wait)
    IO.puts("Target apoapsis reached.")
    Control.set_throttle(control, 0.0)

    # Wait until out of atmosphere:
    IO.puts("Coasting out of atmosphere ...")
    while(Stream.wait(s_altitude) < 70500, do: :wait)

    # Plan circularization burn (using vis-viva equation):
    IO.puts("Planning circularization burn")
    mu = Orbit.body(orbit) |> CelestialBody.gravitational_parameter()
    r = Orbit.apoapsis(orbit)
    a1 = Orbit.semi_major_axis(orbit)
    a2 = r
    v1 = :math.sqrt(mu * (2.0 / r - 1.0 / a1))
    v2 = :math.sqrt(mu * (2.0 / r - 1.0 / a2))
    delta_v = v2 - v1
    IO.puts("Node plotted: #{format_float(delta_v, 1)} m/s of delta-v.")

    # Create circularization node:
    node_ut = Stream.get(s_ut) + Orbit.time_to_apoapsis(orbit)
    # `node` is an Elixir builtin, but it's not a reserved word, so.
    node = Control.add_node(control, node_ut, prograde: delta_v)

    # Calculate burn time (using rocket equation):
    f = Vessel.available_thrust(vessel)
    isp = Vessel.specific_impulse(vessel) * 9.82
    m0 = Vessel.mass(vessel)
    m1 = m0 / :math.exp(delta_v / isp)
    flow_rate = f / isp
    burn_time = (m0 - m1) / flow_rate
    IO.puts("Burn time: #{format_float(burn_time, 2)} seconds.")

    # Orientate ship:
    AutoPilot.set_reference_frame(autopilot, Node.reference_frame(node))
    AutoPilot.set_target_direction(autopilot, {0, 1, 0})
    # Note that AutoPilot.wait sometimes returns immediately, without waiting.
    # It's an old bug in kRPC, not a bug in this code.
    #
    # We can fix it by monitoring the error amount.
    # Doesn't need to be a stream, since it should only get called two or three times.
    while AutoPilot.error(autopilot) |> abs > 1.0 do
      # Repeatedly call `wait` until under 1 degree of error.
      IO.puts("Orientating ship for circularization burn ...")
      AutoPilot.wait(autopilot)
    end

    # Warp until burn minus 5 seconds:
    IO.puts("Waiting until circularization burn ...")
    burn_ut = node_ut - burn_time / 2.0
    lead_time = 5
    SpaceCenter.warp_to(conn, burn_ut - lead_time)

    # Wait until burn:
    IO.puts("Ready to execute burn in 5 seconds.")
    while(Stream.wait(s_ut) < burn_ut, do: :wait)

    # Execute burn:
    IO.puts("Executing burn ...")
    Control.set_throttle(control, 1.0)
    # burn_ut is the start of the burn, and burn_time is the duration,
    # so this waits until 0.1 seconds before the burn should end.
    while(Stream.wait(s_ut) < burn_ut + burn_time - 0.1, do: :wait)

    # Reduce throttle and burn until node is no longer pointing prograde:
    remaining_delta_v = Node.remaining_delta_v(node)
    IO.puts("Fine tuning, #{format_float(remaining_delta_v, 1)} m/s remaining ...")
    Control.set_throttle(control, 0.05)
    s_remaining_burn = Node.remaining_burn_vector(node) |> Stream.stream()
    while(Stream.wait(s_remaining_burn) |> elem(1) > 0.0, do: :wait)

    # Cut throttle and delete node.
    Control.set_throttle(control, 0.0)
    remaining_delta_v = Node.remaining_delta_v(node)
    Node.remove(node)

    IO.puts("""

    Apoapsis:      #{round(Orbit.apoapsis_altitude(orbit) / 1000)}km
    Periapsis:     #{round(Orbit.periapsis_altitude(orbit) / 1000)}km
    Burn accuracy: #{format_float(remaining_delta_v, 1)} m/s remaining

    Launch complete.
    """)
  end

  defp format_integer(int) do
    round(int)
    |> :erlang.integer_to_list()
    |> Enum.reverse()
    |> Enum.chunk_every(3)
    |> Enum.join(",")
    |> String.reverse()
  end

  defp format_float(float, decimals) do
    :erlang.float_to_binary(float, decimals: decimals)
  end
end

Example.run(&LaunchIntoOrbit.launch/1, "Launch into orbit")
