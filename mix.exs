defmodule RedixSharding.Mixfile do
  use Mix.Project

  @description "A wrapper of Redix with sharding & pooling support"

  @repo_url "https://github.com/xxuejie/redix_sharding"

  @version "0.1.0"

  def project do
    [app: :redix_sharding,
     version: @version,
     elixir: "~> 1.4",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),

     # Hex
     package: package(),
     description: @description]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger, :redix]]
  end

  defp package() do
    [maintainers: ["Xuejie Xiao"],
     licenses: ["MIT"],
     links: %{"GitHub" => @repo_url}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:redix, "~> 0.6.0"}]
  end
end
