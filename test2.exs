# Test throughput of active/nonblocking PipeliningConnection class.
# Multiple requests are sent on the wire at once, increasing concurrency
# and reducing the effect of network latency and round-trip processing time.

conn = SpaceEx.PipeliningConnection.connect!("192.168.68.6", 50000)

counts = 
  (1..10000)
  |> Task.async_stream(fn _ ->
    {:ok, bytes} = SpaceEx.PipeliningConnection.call_rpc(conn, "KRPC", "GetStatus")
    status = SpaceEx.Protobufs.Status.decode(bytes)
    status.rpcs_executed
  end, max_concurrency: 1000)
  |> Enum.map(fn {:ok, count} -> count end)
  |> Enum.uniq

IO.inspect(counts)
IO.inspect(Enum.count(counts))
