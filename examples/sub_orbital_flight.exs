# This is a literal translation of the example SubOrbitalFlight.py script
# included in the kRPC source tree.
#
# You probably shouldn't try to write SpaceEx code this way.  Consider making
# use of multiple Elixir processes to watch for various events, independent of
# each other, rather than in sequence.
#
# Despite this, it's not nearly as bad as the mess that is
# `launch_into_orbit.exs`.  The use of events -- and the hardcoded sequence,
# rather than monitoring a bunch of aspects at once -- keeps things much
# cleaner.
#
# There have been some syntax improvements since this script was originally
# ported, some of which should allow the code to be cleaned up somewhat, but
# that cleanup is still pending.  I'll do a cleanup pass once we've reached a
# stable v1.0.0 API.
#
# This script should be used with the included "sub_orbital_flight.craft"
# craft, due to the hardcoded staging sequence.

defmodule SubOrbitalFlight do
  require SpaceEx.Procedure

  alias SpaceEx.{Procedure, Event}

  alias SpaceEx.KRPC.Expression
  alias SpaceEx.SpaceCenter

  alias SpaceEx.SpaceCenter.{
    Vessel,
    Control,
    AutoPilot,
    Flight,
    Resources,
    Orbit,
    CelestialBody
  }

  def launch(conn) do
    vessel = SpaceCenter.active_vessel(conn)
    autopilot = Vessel.auto_pilot(vessel)
    resources = Vessel.resources(vessel)
    control = Vessel.control(vessel)
    flight = Vessel.flight(vessel)
    orbit = Vessel.orbit(vessel)

    AutoPilot.target_pitch_and_heading(autopilot, 90, 90)
    AutoPilot.engage(autopilot)
    Control.set_throttle(control, 1.0)
    Process.sleep(1)

    IO.puts("Launch!")
    Control.activate_next_stage(control)

    # Wait until SRBs exhausted:
    fuel_amount = Resources.amount(resources, "SolidFuel") |> Procedure.create()

    expr =
      Expression.less_than(
        conn,
        Expression.call(conn, fuel_amount),
        Expression.constant_float(conn, 0.1)
      )

    Event.create(conn, expr) |> Event.wait()

    IO.puts("Booster separation")
    Control.activate_next_stage(control)

    # Wait until above 10,000m altitude:
    mean_altitude = Flight.mean_altitude(flight) |> Procedure.create()

    expr =
      Expression.greater_than(
        conn,
        Expression.call(conn, mean_altitude),
        Expression.constant_double(conn, 10_000)
      )

    Event.create(conn, expr) |> Event.wait()

    IO.puts("Gravity turn")
    AutoPilot.target_pitch_and_heading(autopilot, 60, 90)

    # Wait until above 100,000 apoapsis:
    apoapsis_altitude = Orbit.apoapsis_altitude(orbit) |> Procedure.create()

    expr =
      Expression.greater_than(
        conn,
        Expression.call(conn, apoapsis_altitude),
        Expression.constant_double(conn, 100_000)
      )

    Event.create(conn, expr) |> Event.wait()

    IO.puts("Launch stage separation")
    Control.set_throttle(control, 0.0)
    Process.sleep(1_000)
    Control.activate_next_stage(control)
    AutoPilot.disengage(autopilot)

    # Wait until under 1,000m altitude:
    srf_altitude = Flight.surface_altitude(flight) |> Procedure.create()

    expr =
      Expression.less_than(
        conn,
        Expression.call(conn, srf_altitude),
        Expression.constant_double(conn, 1_000)
      )

    Event.create(conn, expr) |> Event.wait()

    Control.activate_next_stage(control)

    kerbin = Orbit.body(orbit)
    kerbin_frame = CelestialBody.reference_frame(kerbin)
    kerbin_flight = Vessel.flight(vessel, reference_frame: kerbin_frame)

    wait_until(fn ->
      surface_altitude = Flight.surface_altitude(flight)
      alti = :erlang.float_to_binary(surface_altitude, decimals: 1)
      IO.puts("Altitude = #{alti} meters")

      Process.sleep(1_000)
      # Break if vertical speed reaches zero (or positive).
      vertical_speed = Flight.vertical_speed(kerbin_flight)
      vertical_speed > -0.1
    end)

    IO.puts("Landed!")
  end

  # Basically an imperative 'until' loop.
  def wait_until(func) do
    Stream.cycle([:ok])
    |> Enum.find(fn _ -> func.() end)
  end
end

conn = SpaceEx.Connection.connect!(name: "Sub-orbital flight", host: "192.168.68.6")

try do
  SubOrbitalFlight.launch(conn)
after
  # If the script dies, the ship will just keep doing whatever it's doing, but
  # without any control or autopilot guidance.  Pausing on completion, but
  # especially on error, makes it clear when a human should take over.
  SpaceEx.KRPC.set_paused(conn, true)
end
