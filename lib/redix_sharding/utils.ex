defmodule RedixSharding.Utils do
  @default_pool "default"

  @unsupported_commands MapSet.new(["CLUSTER", "READONLY", "READWRITE",
                                    "AUTH", "QUIT", "SELECT",
                                    "KEYS", "MOVE", "SORT", "WAIT",
                                    # TODO: disable blocking actions for now
                                    "BLPOP", "BRPOP", "BRPOPLPUSH",
                                    "PSUBSCRIBE", "PUBSUB", "PUBLISH",
                                    "PUNSUBSCRIBE", "SUBSCRIBE", "UNSUBSCRIBE",
                                    "SCRIPT",
                                    "BGREWRITEAOF", "BGSAVE", "CLIENT", "COMMAND", "CONFIG",
                                    "DBSIZE", "DEBUG", "FLUSHALL", "FLUSHDB",
                                    "LASTSAVE", "MONITOR", "ROLE", "SAVE", "SHUTDOWN",
                                    "SLAVEOF", "SLOWLOG", "SYNC",
                                    "DISCARD", "EXEC", "MULTI", "UNWATCH", "WATCH", "MIGRATE"])

  @special_commands %{
    "ECHO" => [-1, -2],
    "PING" => [-1, -2],
    "PFCOUNT" => [1, -1],
    "PFMERGE" => [1, -1],
    "DEL" => [1, -1],
    "EXISTS" => [1, -1],
    "OBJECT" => [2, 2],
    "RANDOMKEY" => [-1, -2],
    "RENAME" => [1, 2],
    "RENAMENX" => [1, 2],
    "RPOPLPUSH" => [1, 2],
    "INFO" => [-1, -2],
    "TIME" => [-1, -2],
    "SDIFF" => [1, -1],
    "SDIFFSTORE" => [1, -1],
    "SINTER" => [1, -1],
    "SINTERSTORE" => [1, -1],
    "SMOVE" => [1, 2],
    "SUNION" => [1, -1],
    "SUNIONSTORE" => [1, -1],
    "BITOP" => [2, -1],
    "MGET" => [1, -1],
    "EVAL" => :eval_keys,
    "EVALSHA" => :eval_keys,
    "ZINTERSTORE" => :zstore_keys,
    "ZUNIONSTORE" => :zstore_keys,
    "MSET" => :mset_keys,
    "MSETNX" => :mset_keys
  }

  def special_commands, do: @special_commands

  def unsupported_commands, do: @unsupported_commands

  def shard_command(command, configs) do
    with {:ok, keys} <- command_keys(command) do
      sharding_keys = Enum.map(keys, &sharding_key(&1))
      if (Enum.uniq_by(sharding_keys, fn {pool, _} -> pool end) |> length) > 1 do
        {:error, :inconsistent_pools}
      else
        pool_name = if length(sharding_keys) > 0, do: List.first(sharding_keys) |> elem(0), else: @default_pool
        case Keyword.get(configs, :pools) |> Map.get(pool_name) do
          nil ->
            {:error, :not_exist_pool}
          pool ->
            shard_size = Keyword.get(pool, :urls) |> length
            shards = Enum.map(sharding_keys, fn {_, str} -> shard(str, shard_size) end) |> Enum.uniq
            if length(shards) > 1 do
              {:error, :inconsistent_shards}
            else
              {:ok, {pool_name, List.first(shards)}}
            end
        end
      end
    end
  end

  def to_integer(i) when is_bitstring(i), do: String.to_integer(i)
  def to_integer(i) when is_integer(i), do: i

  def to_string(s) when is_atom(s), do: Atom.to_string(s)
  def to_string(s) when is_bitstring(s), do: s

  defp command_keys(command) when is_list(command) do
    cmd = List.first(command)
    if MapSet.member?(unsupported_commands(), cmd) do
      {:error, :unsupported_command}
    else
      keys = case Map.get(special_commands(), cmd) do
        [start_index, _] when start_index < 0 -> []
        [start_index, slice_length] when slice_length < 0 ->
          Enum.slice(command, start_index, length(command) - start_index + 1 +  slice_length)
        [start_index, slice_length] ->
          Enum.slice(command, start_index, slice_length)
        fun when is_atom(fun) and (not is_nil(fun)) ->
          apply(__MODULE__, fun, [command])
        _ ->
          Enum.slice(command, 1, 1)
      end
      {:ok, keys}
    end
  end

  defp shard(str, num) do
    :erlang.crc32(str) |> rem(num)
  end

  defp sharding_key(key) do
    case Regex.scan(~r/\{((?:([^@]+)@)?(?:[^\}]+))\}/, key) do
      [[_, str]] -> {@default_pool, str}
      [[_, str, pool]] -> {pool, str}
      _ -> {@default_pool, key}
    end
  end

  # Those functions should be internal only, the reason they are public is
  # we need to use apply to call them dynamically
  def eval_keys(keys) do
    Enum.slice(keys, 3, (Enum.at(keys, 2) |> to_integer))
  end

  def zstore_keys(keys) do
    [Enum.at(keys, 1)] ++ Enum.slice(keys, 3, (Enum.at(keys, 2) |> to_integer))
  end

  def mset_keys(keys) do
    Enum.drop(keys, 1) |> Enum.chunk(2) |> Enum.map(fn [a, _] -> a end)
  end
end
