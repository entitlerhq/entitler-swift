#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
swift format lint --strict --recursive \
  Sources Tests Plugins Package.swift \
  examples/Package.swift examples/quickstart examples/pricing-page examples/in-app \
  examples/metered-work examples/offline examples/billing examples/swiftui-view-model \
  examples/testing examples/generated-features
