#!/bin/bash

export CLUB_NAME=${CLUB_NAME:-$USER}

exe=$(cat $(basename $PWD).cabal | grep executable | head -n 1 | cut -d' ' -f2)
echo "Running: $exe"

stack build
path=$(stack path --local-install-root)

${path}/bin/${exe} \
  --kafka-broker localhost:9092 \
  --kafka-schema-registry http://localhost:8081 \
  --kafka-group-id ${CLUB_NAME}--submissions-indexer-group \
  --input-topic ${CLUB_NAME}--atlasdos-submissions-balanced \
  --xml-index-bucket ${CLUB_NAME}--atlasdos-submissions-index-bucket
  --kafka-poll-timeout-ms 10000 \
  --log-level LevelDebug
