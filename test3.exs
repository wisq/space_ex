# Test the safety of the PipeliningConnection.
# By alternating calls to GetClientID and GetClientName,
# and demanding the correct response to each,
# we ensure that despite our pipelining,
# requests are never processed or replied out of order.

conn = SpaceEx.PipeliningConnection.connect!("192.168.68.6", 50000)

{:ok, expected_client_id} = SpaceEx.PipeliningConnection.call_rpc(conn, "KRPC", "GetClientID")
{:ok, expected_name}      = SpaceEx.PipeliningConnection.call_rpc(conn, "KRPC", "GetClientName")

statuses = 
  (1..10000)
  |> Task.async_stream(fn n ->
    if rem(n, 2) == 0 do
      {:ok, ^expected_client_id} = SpaceEx.PipeliningConnection.call_rpc(conn, "KRPC", "GetClientID")
      true
    else
      {:ok, ^expected_name}      = SpaceEx.PipeliningConnection.call_rpc(conn, "KRPC", "GetClientName")
      true
    end
  end, max_concurrency: 1000)
  |> Enum.uniq

IO.inspect(statuses)
