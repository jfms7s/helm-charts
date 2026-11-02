#!/usr/bin/env bash
# Prints the values-file sets a chart is rendered with in CI, one render per
# line as `-f <file> [-f <file>]`, by convention (no per-chart lists):
#   - no ci/test-values.yaml: values.yaml is the base;
#   - else ci/test-values.yaml is the base (the chart's dummy credentials,
#     image or volume that it refuses to render without);
#   - the base on its own, then each other ci/*-values.yaml layered on it.
# Usage: scripts/chart-values-sets.sh <chart-dir>
set -euo pipefail
dir=${1:?usage: $0 <chart-dir>}
base="$dir/values.yaml"
[ -f "$dir/ci/test-values.yaml" ] && base="$dir/ci/test-values.yaml"
echo "-f $base"
for f in "$dir"/ci/*-values.yaml; do
  [ -e "$f" ] || continue
  [ "$f" = "$dir/ci/test-values.yaml" ] && continue
  echo "-f $base -f $f"
done
