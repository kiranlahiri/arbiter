#!/usr/bin/env bash
set -euo pipefail

# Generate Go protobuf code from proto/*.proto
# Requires: protoc, protoc-gen-go (install with `go install google.golang.org/protobuf/cmd/protoc-gen-go@latest`)

OUT_DIR="./proto"
mkdir -p "$OUT_DIR"

protoc \
  --proto_path=./proto \
  --go_out=${OUT_DIR} --go_opt=paths=source_relative \
  proto/*.proto

echo "Generated Go protobuf files in ${OUT_DIR}"
