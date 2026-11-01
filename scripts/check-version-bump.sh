#!/usr/bin/env bash
# Fail if a chart changed since <base-ref> without raising its Chart.yaml version.
#
# chart-releaser runs with skip_existing, so a chart whose content changed but
# whose version did not is silently never published. This catches that before
# merge.
#
# Usage: scripts/check-version-bump.sh <base-ref>     (e.g. origin/main)
#
# Compares the merge-base of <base-ref> and HEAD with the working tree, so it
# sees committed and uncommitted changes to tracked files. Changes only under a
# chart's tests/ or ci/ do not change what the chart renders and need no bump;
# anything else under charts/<chart>/ (templates, values, Chart.yaml, README,
# .helmignore, files) does. A chart that is new or deleted since the base passes.
set -euo pipefail

base_ref=${1:?usage: $0 <base-ref>}

merge_base=$(git merge-base "$base_ref" HEAD) || {
  echo "check-version-bump: cannot find a merge-base between '$base_ref' and HEAD (shallow clone? fetch with fetch-depth: 0)" >&2
  exit 2
}

chart_version() { # reads a Chart.yaml on stdin, prints its top-level version
  sed -n -E 's/^version:[[:space:]]*["'\'']?([^"'\''[:space:]#]+).*/\1/p' | head -n1
}

changed_charts=$(
  git diff --name-only "$merge_base" -- charts/ \
    | awk -F/ 'NF >= 3 && $3 != "tests" && $3 != "ci" { print $2 }' \
    | sort -u
)

if [ -z "$changed_charts" ]; then
  echo "check-version-bump: no chart content changed since $base_ref"
  exit 0
fi

failed=0
for chart in $changed_charts; do
  chart_yaml="charts/$chart/Chart.yaml"
  if ! git cat-file -e "$merge_base:$chart_yaml" 2>/dev/null; then
    echo "ok    $chart: new chart"
    continue
  fi
  if [ ! -f "$chart_yaml" ]; then
    echo "ok    $chart: removed"
    continue
  fi
  old=$(git show "$merge_base:$chart_yaml" | chart_version)
  new=$(chart_version < "$chart_yaml")
  if [ -z "$old" ] || [ -z "$new" ]; then
    echo "FAIL  $chart: cannot read version (base '$old', now '$new') from $chart_yaml"
    failed=1
  elif [ "$old" != "$new" ] && [ "$(printf '%s\n%s\n' "$old" "$new" | sort -V | tail -n1)" = "$new" ]; then
    echo "ok    $chart: $old -> $new"
  else
    echo "FAIL  $chart: content changed but version is $new (was $old at $base_ref); bump version in $chart_yaml"
    failed=1
  fi
done

if [ "$failed" -ne 0 ]; then
  echo >&2
  echo "check-version-bump: a changed chart was not version-bumped; chart-releaser (skip_existing) would never publish it." >&2
  exit 1
fi
