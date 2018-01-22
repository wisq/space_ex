defmodule SpaceEx.Mixfile do
  use Mix.Project

  def project do
    [
      app: :space_ex,
      version: "0.5.1",
      elixir: "~> 1.5",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: docs(),
      description: description(),
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      preferred_cli_env: ["git.test": :test]
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
      links: %{GitHub: "https://github.com/wisq/space_ex"}
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "TODO.md"
      ],
      before_closing_head_tag: fn _ ->
        ~S(<script type="text/javascript" src="https://cdnjs.cloudflare.com/ajax/libs/mathjax/2.7.1/MathJax.js?config=TeX-AMS-MML_HTMLorMML"></script>)
      end,
      groups_for_modules: [
        "Core API": ~r/^SpaceEx\.(KRPC|SpaceCenter)(\.|$)/,
        UI: ~r/^SpaceEx\.(UI|Drawing)(\.|$)/,
        Mods: ~r/^SpaceEx\.(RemoteTech|KerbalAlarmClock|InfernalRobotics)(\.|$)/
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"},
      {:exprotobuf, "~> 1.2.9"},
      {:socket, "~> 0.3"},
      {:poison, "~> 3.1"},
      {:floki, "~> 0.19.0"},
      {:ex_doc, "~> 0.10", only: :dev},
      {:mix_test_watch, "~> 0.5", only: :dev, runtime: false},
      {:briefly, "~> 0.3", only: :test, runtime: false}
    ]
  end
end
