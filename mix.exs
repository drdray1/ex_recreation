defmodule ExRecreation.MixProject do
  use Mix.Project

  @version "0.1.1"
  @source_url "https://github.com/drdray1/ex_recreation"

  def project do
    [
      app: :ex_recreation,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env()),
      test_coverage: test_coverage(),

      # Hex
      description: "Elixir client for the recreation.gov permit and campground availability API",
      package: package(),

      # Docs
      name: "ExRecreation",
      source_url: @source_url,
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp test_coverage do
    [
      threshold: 90,
      summary: [threshold: 90],
      # A thin CLI over already-covered library functions; all it adds is
      # argument parsing and `Mix.shell().info/1` formatting, and testing that
      # would mean asserting on captured stdout rather than on behaviour.
      ignore_modules: [Mix.Tasks.Recreation.Check]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:jason, "~> 1.4"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:plug, "~> 1.14", only: :test},
      # Only needed to resolve "America/New_York" in tests. Consumers supply
      # their own time zone database; the library never depends on this at
      # runtime, and every function except `Trips.release_at/2` works without one.
      {:tzdata, "~> 1.1", only: [:dev, :test]}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md)
    ]
  end

  defp docs do
    [
      main: "ExRecreation",
      extras: ["README.md"],
      groups_for_modules: [
        API: [
          ExRecreation.Availability,
          ExRecreation.Permits,
          ExRecreation.Search
        ],
        Planning: [
          ExRecreation.Trips
        ],
        Client: [
          ExRecreation.Client,
          ExRecreation.Request
        ]
      ]
    ]
  end
end
