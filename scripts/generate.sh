#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift run generate-wire openapi.json Sources/Entitler/Wire.gen.swift
swift format --in-place Sources/Entitler/Wire.gen.swift
