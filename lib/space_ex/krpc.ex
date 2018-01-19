defmodule SpaceEx.KRPC do
  use SpaceEx.Gen,
    name: "KRPC",
    overrides: %{
      add_stream: [:nodoc],
      add_event: [:nodoc],
      remove_stream: [:nodoc],
      set_stream_rate: [:nodoc],
      start_stream: [:nodoc]
    }
end
