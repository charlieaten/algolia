defmodule Algolia.MixProject do
  use Mix.Project

  def project do
    [
      app: :algolia,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:algoliax, "~> 0.10"},
      {:ash, "~> 3.19"},
      {:spark, "~> 2.2"},
      {:sourceror, "~> 1.12", only: [:dev, :test]}
    ]
  end

  defp aliases do
    [
      test: ["test"]
    ]
  end
end
