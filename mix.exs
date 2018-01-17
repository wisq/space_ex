defmodule SpaceEx.Mixfile do
  use Mix.Project

  def project do
    [
      app: :space_ex,
      version: "0.3.0",
      elixir: "~> 1.5",
      start_permanent: Mix.env == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp description do
    """
    SpaceEx allows you to write Elixir code to control virtual
    rockets in Kerbal Space Program, by connecting to the kRPC mod.
    """
  end

  defp package do
    [
      files: ["lib", "mix.exs", "README.md", "LICENSE"],
      maintainers: ["Adrian Irving-Beer"],
      licenses: ["Apache Version 2.0"],
      links: %{"GitHub": "https://github.com/wisq/space_ex"},
    ]
  end

  defp docs do
    [
      before_closing_head_tag: fn _ ->
        ~S(<script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS-MML_HTMLorMML"></script>)
      end,
      groups_for_modules: [
        "Core API": ~r/^SpaceEx\.(KRPC|SpaceCenter)(\.|$)/,
        "UI": ~r/^SpaceEx\.(UI|Drawing)(\.|$)/,
        "Mods": ~r/^SpaceEx\.(RemoteTech|KerbalAlarmClock|InfernalRobotics)(\.|$)/,
      ],
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:exprotobuf, "~> 1.2.9"},
      {:socket, "~> 0.3"},
      {:poison, "~> 3.1"},
      {:ex_doc, "~> 0.10", only: :dev},
      {:floki, "~> 0.19.0"},
    ]
  end
end
