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
# The main thing getting in the way of good-looking code here is the constant
# need for `{:ok, _} = ...` call syntax, especially since it makes nested
# Expression code very difficult.  I'm moving away from that in more recent
# modules like `Stream` and `Event`, but I'll be getting rid of it entirely
# for the v1.0.0 release and just raising on error.
#
# Also, function naming needs work, especially all the `static_*` functions.
#
# This script should be used with the included "sub_orbital_flight.craft"
# craft, due to the hardcoded staging sequence.

defmodule SubOrbitalFlight do
  require SpaceEx.Procedure

  alias SpaceEx.{Procedure, Event}

  alias SpaceEx.KRPC.Expression
  alias SpaceEx.SpaceCenter
  alias SpaceEx.SpaceCenter.{
    Vessel, Control, AutoPilot,
    Flight, Resources, Orbit,
    CelestialBody,
  }

  def launch(conn) do
    {:ok, vessel}    = SpaceCenter.get_active_vessel(conn)
    {:ok, autopilot} = Vessel.get_auto_pilot(conn, vessel)
    {:ok, resources} = Vessel.get_resources(conn, vessel)
    {:ok, control}   = Vessel.get_control(conn, vessel)
    {:ok, surf_ref}  = Vessel.get_surface_reference_frame(conn, vessel)
    {:ok, flight}    = Vessel.flight(conn, vessel, surf_ref)
    {:ok, orbit}     = Vessel.get_orbit(conn, vessel)

    {:ok, _} = AutoPilot.target_pitch_and_heading(conn, autopilot, 90, 90)
    {:ok, _} = AutoPilot.engage(conn, autopilot)
    {:ok, _} = Control.set_throttle(conn, control, 1.0)
    Process.sleep(1)

    IO.puts("Launch!")
    {:ok, _} = Control.activate_next_stage(conn, control)

    # Wait until SRBs exhausted:
    fuel_amount = Resources.amount(conn, resources, "SolidFuel") |> Procedure.create
    {:ok, expr_call}  = Expression.static_call(conn, fuel_amount)
    {:ok, expr_value} = Expression.static_constant_float(conn, 0.1)
    {:ok, expr}       = Expression.static_less_than(conn, expr_call, expr_value)
    Event.create(conn, expr) |> Event.wait

    IO.puts("Booster separation")
    {:ok, _} = Control.activate_next_stage(conn, control)

    # Wait until above 10,000m altitude:
    mean_altitude = Flight.get_mean_altitude(conn, flight) |> Procedure.create
    {:ok, expr_call}  = Expression.static_call(conn, mean_altitude)
    {:ok, expr_value} = Expression.static_constant_double(conn, 10_000)
    {:ok, expr}       = Expression.static_greater_than(conn, expr_call, expr_value)
    Event.create(conn, expr) |> Event.wait

    IO.puts("Gravity turn")
    {:ok, _} = AutoPilot.target_pitch_and_heading(conn, autopilot, 60, 90)

    # Wait until above 100,000 apoapsis:
    apoapsis_altitude = Orbit.get_apoapsis_altitude(conn, orbit) |> Procedure.create
    {:ok, expr_call}  = Expression.static_call(conn, apoapsis_altitude)
    {:ok, expr_value} = Expression.static_constant_double(conn, 100_000)
    {:ok, expr}       = Expression.static_greater_than(conn, expr_call, expr_value)
    Event.create(conn, expr) |> Event.wait

    IO.puts("Launch stage separation")
    {:ok, _} = Control.set_throttle(conn, control, 0.0)
    Process.sleep(1_000)
    {:ok, _} = Control.activate_next_stage(conn, control)
    {:ok, _} = AutoPilot.disengage(conn, autopilot)

    # Wait until under 1,000m altitude:
    srf_altitude = Flight.get_surface_altitude(conn, flight) |> Procedure.create
    {:ok, expr_call}  = Expression.static_call(conn, srf_altitude)
    {:ok, expr_value} = Expression.static_constant_double(conn, 1_000)
    {:ok, expr}       = Expression.static_less_than(conn, expr_call, expr_value)
    Event.create(conn, expr) |> Event.wait

    {:ok, _} = Control.activate_next_stage(conn, control)

    {:ok, kerbin} = Orbit.get_body(conn, orbit)
    {:ok, kerbin_frame} = CelestialBody.get_reference_frame(conn, kerbin)
    {:ok, kerbin_flight} = Vessel.flight(conn, vessel, kerbin_frame)

    wait_until(fn ->
      {:ok, surface_altitude} = Flight.get_surface_altitude(conn, flight)
      alti = :erlang.float_to_binary(surface_altitude, decimals: 1)
      IO.puts("Altitude = #{alti} meters")

      Process.sleep(1_000)
      # Break if vertical speed reaches zero (or positive).
      {:ok, vertical_speed} = Flight.get_vertical_speed(conn, kerbin_flight)
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
