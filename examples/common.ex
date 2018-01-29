defmodule Example do
  defp parse_args(caller_env) do
    {options, args, invalid} =
      OptionParser.parse(System.argv(), strict: [host: :string, observer: :boolean])

    unless invalid == [] do
      IO.puts("")

      Enum.each(invalid, fn {opt, _} ->
        case opt do
          "--host" -> "--host should be followed by a hostname or IP."
          opt -> "Invalid option: #{opt}"
        end
        |> IO.puts()
      end)

      usage(caller_env)
    end

    unless args == [] do
      IO.puts("\nThis script does not expect any (non-option) arguments.")
      usage(caller_env)
    end

    options
  end

  defp usage(caller_env) do
    whoami = Path.relative_to_cwd(caller_env.file)
    IO.puts("\nUsage: mix run #{whoami} [--host 1.2.3.4] [--observer]\n")
    exit(:normal)
  end

  def run(caller_env, module_fn, name) do
    options = parse_args(caller_env)
    host = options[:host] || "127.0.0.1"
    conn = SpaceEx.Connection.connect!(name: name, host: host)

    if options[:observer], do: :observer.start()

    try do
      SpaceEx.KRPC.set_paused(conn, false)
      module_fn.(conn)
      Process.sleep(1_000)
    after
      # If the script dies, the ship will just keep doing whatever it's doing,
      # but without any control or autopilot guidance.  Pausing on completion,
      # but especially on error, makes it clear when a human should take over.
      SpaceEx.KRPC.set_paused(conn, true)
    end
  end
end

defmodule Loop do
  # Credit to "Metaprogramming Elixir" by Chris McCord.
  defmacro while(expression, do: block) do
    quote do
      try do
        for _ <- Elixir.Stream.cycle([:ok]) do
          if unquote(expression) do
            unquote(block)
          else
            Loop.break()
          end
        end
      catch
        :break -> :ok
      end
    end
  end

  # Same thing, but with persistent state between loops.
  defmacro while_state(initial, expression, do: block) do
    quote do
      try do
        Elixir.Stream.cycle([unquote(initial)])
        |> Enum.reduce(fn _, var!(state) ->
          if unquote(expression) do
            unquote(block)
          else
            Loop.break()
          end
        end)
      catch
        :break -> :ok
      end
    end
  end

  def break, do: throw(:break)
end
