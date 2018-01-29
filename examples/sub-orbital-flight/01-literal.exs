# This is a literal translation of the example SubOrbitalFlight.py script
# included in the kRPC source tree.
#
# You probably shouldn't try to write SpaceEx code this way.  Consider making
# use of multiple Elixir processes to watch for various events, independent of
# each other, rather than in sequence.
#
# Despite this, it's not nearly as bad as the mess that is the literal version
# of "launch into orbit".  The use of events -- and the hardcoded sequence,
# rather than monitoring a bunch of aspects at once -- keeps things much
# cleaner.
#
# This script should be used with the included "sub_orbital_flight.craft"
# craft, due to the hardcoded staging sequence.

# Get some common modules like arg parsing, `Loop`, etc.
Path.expand("../common.ex", __DIR__)
|> Code.load_file()

defmodule SubOrbitalFlight do
  require Loop
  import Loop

  use SpaceEx.ExpressionBuilder

  alias SpaceEx.{
    SpaceCenter,
    ExpressionBuilder,
    Event
  }

  alias SpaceCenter.{
    Vessel,
    Control,
    AutoPilot,
    Flight,
    Resources,
    Orbit,
    CelestialBody
  }

  # Aim for a maximum altitude of 100km.
  @target_apoapsis 100_000
  # Begin pitch-over to 60 degrees at 10km altitude.
  # The original script calls this a gravity turn, but it's really not.
  # ("Gravity turn" may be the most misused term in the Kerbal community.)
  @pitch_over_altitude 10_000
  # Deploy parachutes at 1500m.
  # The original script has them deploy at 1000m, but I find this is often too late.
  # Even 1500m only leaves us with 100m clearance sometimes.  Maybe network latency.
  @parachute_altitude 1_500

  def launch(conn) do
    vessel = SpaceCenter.active_vessel(conn)

    autopilot = Vessel.auto_pilot(vessel)
    AutoPilot.target_pitch_and_heading(autopilot, 90, 90)
    AutoPilot.engage(autopilot)
    control = Vessel.control(vessel)
    Control.set_throttle(control, 1.0)
    Process.sleep(1_000)

    IO.puts("Launch!")
    Control.activate_next_stage(control)

    # Wait until SRBs exhausted:
    ExpressionBuilder.build conn do
      Vessel.resources(vessel) |> Resources.amount("SolidFuel") < float(0.1)
    end
    |> Event.create()
    |> Event.wait()

    IO.puts("Booster separation")
    Control.activate_next_stage(control)

    # Wait until above target altitude:
    flight = Vessel.flight(vessel)

    ExpressionBuilder.build conn do
      Flight.mean_altitude(flight) > double(@pitch_over_altitude)
    end
    |> Event.create()
    |> Event.wait()

    IO.puts("Pitching over to 60 degrees")
    AutoPilot.target_pitch_and_heading(autopilot, 60, 90)

    # Wait until above target apoapsis:
    orbit = Vessel.orbit(vessel)

    ExpressionBuilder.build conn do
      Orbit.apoapsis_altitude(orbit) > double(@target_apoapsis)
    end
    |> Event.create()
    |> Event.wait()

    IO.puts("Launch stage separation")
    Control.set_throttle(control, 0.0)
    Process.sleep(1_000)
    Control.activate_next_stage(control)
    AutoPilot.disengage(autopilot)

    # Wait until under 1,000m altitude:
    ExpressionBuilder.build conn do
      Flight.surface_altitude(flight) < double(@parachute_altitude)
    end
    |> Event.create()
    |> Event.wait()

    Control.activate_next_stage(control)

    body_frame = Orbit.body(orbit) |> CelestialBody.reference_frame()
    body_flight = Vessel.flight(vessel, reference_frame: body_frame)

    while Flight.vertical_speed(body_flight) < 0.1 do
      surface_altitude = Flight.surface_altitude(flight)
      alti = :erlang.float_to_binary(surface_altitude, decimals: 1)
      IO.puts("Altitude = #{alti} meters")

      Process.sleep(1_000)
    end

    IO.puts("Landed!")
  end
end

Example.run(&SubOrbitalFlight.launch/1, "Sub-orbital flight")
