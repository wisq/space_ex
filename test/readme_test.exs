defmodule ReadmeTest do
  use ExUnit.Case, async: true

  test "README deps example references current version" do
    expected = SpaceEx.Mixfile.project()[:version]
    actual = get_readme_version()
    assert expected == actual
  end

  def get_readme_version() do
    readme = File.read!("README.md")

    case Regex.run(~r/^\s+{:space_ex, "~> ([0-9\.]+)"}\s*$/m, readme) do
      [_, version] -> version
      nil -> nil
    end
  end
end
