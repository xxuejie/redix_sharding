defmodule RedixSharding.Mixfile do
  use Mix.Project

  @description "A wrapper of Redix with sharding & pooling support"

  @repo_url "https://github.com/xxuejie/redix_sharding"

  @version "0.1.1"

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

  def application do
    [extra_applications: [:logger, :redix]]
  end

  defp package() do
    [maintainers: ["Xuejie Xiao"],
     licenses: ["MIT"],
     links: %{"GitHub" => @repo_url}]
  end

  defp deps do
    [{:redix, "~> 0.6.0"},
     {:ex_doc, "~> 0.14", only: :dev}]
  end
end
