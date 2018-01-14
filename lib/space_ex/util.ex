defmodule SpaceEx.Util do
  @moduledoc false

  @regex_multi_uppercase ~r'([A-Z]+)([A-Z][a-z0-9])'
  @regex_single_uppercase ~r'([a-z0-9])([A-Z])'

  # Turn a CamelCaseString into a snake_case_string.
  def to_snake_case(name) do
    name
    |> String.replace(@regex_single_uppercase, "\\1_\\2")
    |> String.replace(@regex_multi_uppercase, "\\1_\\2")
    |> String.downcase
  end

  # Similar to file basename:
  #
  #   module_basename(Foo.Bar.Baz) = "Baz"
  #
  # Note that the result is a string, not an atom.

  def module_basename(mod) do
    Module.split(mod)
    |> List.last
  end
end
