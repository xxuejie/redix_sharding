# RedixSharding

Drop-in replacement for [Redix](https://github.com/whatyouhide/redix) with sharding and pooling support

## Usage

```elixir
opts = [
  pools: [
    default: [
      urls: ["redis://localhost:6379", "redis://localhost:6380", "redis://localhost:6381", "redis://localhost:6382"],
      connection: 1],
    index: [
      urls: ["redis://localhost:6383", "redis://localhost:6384"],
      connection: 2]
  ]
]

RedixSharding.start_link(opts)

RedixSharding.command(["INCRBY", "{default@foo5}", 1])

RedixSharding.pipeline([["INCRBY", "{default@foo5}", 1]])
```

In the `opts` configuration above, we have configured 2 pools:

* Pool `default` has 4 shards, for each shard we will maintain 1 active connection in the pool
* Pool `index` has 2 shards, for each shard we will maintain 2 active connections, requests send to each shard will be distributed between 2 active connections

## Sharding Rule:

There are 2 concepts you need to grasp here:

* `pool_name`: denotes the name of the pool to send requests, different pools are totally separated from each other
* `shard_key`: the key used to calculate the shard current key goes to, we will do a CRC32 calculation on the shard key, the mod the number of shards in the pool to get the shard index for current key. Notice due to following rules, a shard key can be the full key or part of the full key.

For commands that will require multiple keys, we will calculate the pool name and shard key for each key, and we would only run the command if all key maps to the same pool and same shard

|full key|pool name|shard key|
|--------|---------|---------|
|Foo:bar|default|Foo:bar|
|Foo{}bar|default|Foo{}bar|
|{Foo}bar|default|Foo|
|{default@Foo}bar|default|default@Foo|
|{index@Foo}bar|index|index@Foo|
|{@Foo}bar|default|@Foo|
|{Foo}:bar:{Baz}|default|Foo|
|{Foo}:bar:{index@Baz}|default|Foo|
