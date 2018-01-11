# Test throughput of passive/blocking Connection class.

conn = SpaceEx.Connection.connect!("192.168.68.6", 50000)

counts = 
  (1..10000)
  |> Task.async_stream(fn _ ->
    {:ok, bytes} = SpaceEx.Connection.call_rpc(conn, "KRPC", "GetStatus")
    status = SpaceEx.Protobufs.Status.decode(bytes)
    status.rpcs_executed
  end, max_concurrency: 1000)
  |> Enum.map(fn {:ok, count} -> count end)
  |> Enum.uniq

IO.inspect(counts)
IO.inspect(Enum.count(counts))
