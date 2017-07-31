[![CircleCI](https://circleci.com/gh/packetloop/attackstream-indexer.svg?style=svg)](https://circleci.com/gh/packetloop/attackstream-indexer)

# attackstream-indexer

Watches incoming attackstream files and creates succinct indexes for them.

This job is expecting a `balanced submissions topic` as its input.
This topic is nprmally produced by `atlasdos-submissions-balancer` job and its expected contract is desctribed in [fileChange.avsc](contract/fileChange.avsc)

## Running locally
`run.sh` script can be used to run job locally.

The following env variables can be used with `run.sh`:

`KAFKA_HOST` (default: `localhost`) - points to Kafka broker that provides an input topic
`CLUB_NAME` (default: `$USER`) - specifies the club name prefix for input and output resources (topics, buckets)

### Examples

Running against `zambia` club locally:

```
$ KAFKA_HOST=172.31.11.250 CLUB_NAME=zambia ./run.sh
```


Running against local dev environment (docker-compose):
```
$ docker-compose up -d
$ ./run.sh
```