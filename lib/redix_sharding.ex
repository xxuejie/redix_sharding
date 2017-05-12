defmodule RedixSharding do
  import Supervisor.Spec, only: [supervise: 2, worker: 3]
  alias RedixSharding.Utils

  @config_worker_id :redix_sharding__config

  def child_spec(opts) do
    supervise(worker_specs(opts), strategy: :one_for_one)
  end

  def start_link(opts) do
    Supervisor.start_link(worker_specs(opts), strategy: :one_for_one)
  end

  def command(cmd) do
    command(nil, cmd)
  end

  def pipeline(cmds) do
    pipeline(nil, cmds)
  end

  def command(conn, command, opts \\ []) do
    case pipeline(conn, [command], opts) do
      {:ok, [resp]} ->
        {:ok, resp}
      error ->
        error
    end
  end

  # For now, we keep conn here for API compatibility with original Redix, in
  # future we might change this to work completely with conn so no central
  # process registration is needed.
  def pipeline(_conn, commands, _opts \\ []) do
    configs = Agent.get(@config_worker_id, &(&1))
    case shard_commands([], commands, configs) do
      {:error, error} ->
        {:error, error}
      sharded_commands ->
        buffers = Enum.with_index(sharded_commands)
        |> Enum.reduce(%{}, fn({{cmd, pool, shard}, index}, acc) ->
          partial_id = partial_worker_id(pool, shard)
          {commands, indices, connection_index} = Map.get(acc, partial_id,
            {[], [], generate_random_connection_index(pool, configs)})
          Map.put(acc, partial_id, {[cmd | commands], [index | indices], connection_index})
        end)
        |> Map.to_list
        response_map = send_buffered_commands(%{}, buffers)
        responses = Enum.map(1..length(sharded_commands), fn(index) ->
          Map.get(response_map, index - 1)
        end)
        {:ok, responses}
    end
  end

  defp generate_random_connection_index(pool_name, configs) do
    connection_size = Keyword.get(configs, :pools) |> Map.get(pool_name) |> Keyword.get(:connection)
    :rand.uniform(connection_size) - 1
  end

  defp send_buffered_commands(response_map, []), do: response_map
  defp send_buffered_commands(response_map, [{partial_id, {reversed_commands, reversed_indices, connection_index}} | buffers]) do
    with {:ok, responses} <- Redix.pipeline(full_worker_id_from_partial_id(partial_id, connection_index),
              Enum.reverse(reversed_commands)) do
      Enum.zip([responses, Enum.reverse(reversed_indices)])
      |> Enum.reduce(response_map, fn ({response, index}, response_map) ->
        Map.put(response_map, index, response)
      end)
      |> send_buffered_commands(buffers)
    end
  end

  defp shard_commands(sharded_commands, [], _), do: Enum.reverse(sharded_commands)
  defp shard_commands(sharded_commands, [cmd | remaining_commands], configs) do
    with {:ok, {pool, shard}} <- Utils.shard_command(cmd, configs),
    do: [{cmd, pool, shard} | sharded_commands] |> shard_commands(remaining_commands, configs)
  end

  defp worker_specs(opts) do
    Enum.flat_map(Keyword.get(opts, :pools, []), fn {name, pool} ->
      pool_specs(name, pool)
    end) ++ [worker(Agent, [fn -> transform_config(opts) end, [name: @config_worker_id]], id: @config_worker_id)]
  end

  defp pool_specs(pool_name, pool) do
    connection_size = Keyword.get(pool, :connection, 1)
    urls = Keyword.get(pool, :urls, [])
    Enum.with_index(urls) |> Enum.flat_map(fn {url, shard_index} ->
      Enum.map(1..connection_size, fn(connection_index) ->
        worker_id = full_worker_id(pool_name, shard_index, connection_index - 1)
        IO.inspect(worker_id)
        worker(Redix, [url, [name: worker_id]], id: worker_id)
      end)
    end)
  end

  defp full_worker_id(pool_name, shard_index, connection_index) do
    partial_worker_id(pool_name, shard_index) |> full_worker_id_from_partial_id(connection_index)
  end

  defp partial_worker_id(pool_name, shard_index) do
    :"redix_sharding_#{pool_name}_#{shard_index}"
  end

  defp full_worker_id_from_partial_id(partial_id, connection_index) do
    :"#{partial_id}_#{connection_index}"
  end

  # Transform all keys in keyword lists from atoms to strings, since pool name comes from
  # user, we don't want to risk creating too many atoms
  defp transform_config(opts) do
    pools = Keyword.get(opts, :pools, [])
    |> Enum.map(fn {name, pool} ->
      {Utils.to_string(name), pool}
    end)
    |> Enum.into(%{})
    Keyword.put(opts, :pools, pools)
  end
end
