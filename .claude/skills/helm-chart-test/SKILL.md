---
name: helm-chart-test
description: Plan, write, and validate helm-unittest tests for a chart in this repo. Discovers chart structure, maps coverage gaps, and applies this repo's helm-unittest conventions.
user-invocable: true
---

# /helm-chart-test [chart] [component]

Use this skill whenever the user asks to add, expand, fix, or review helm-unittest
coverage for `charts/common`, `charts/affine-helm`, or `charts/patchmon-helm`, or
when a chart feature change (e.g. via the `compose-to-chart` skill) needs matching
rendered-manifest tests.

## Argument Handling

**During feature implementation**, infer the chart from the files being changed
(`charts/<chart>/templates/...`). Add or update focused tests for the affected
rendered behavior without pausing for broad coverage analysis, unless the requested
behavior is ambiguous.

**If no arguments are provided for a standalone test task**, ask the user which
chart they want to work on (`common`, `affine-helm`, or `patchmon-helm`).

**If only `<chart>` is provided for a standalone coverage audit**, run the
discovery and coverage analysis below before asking any questions.

**If `<chart> <component>` is provided**, inspect that template file and choose
the relevant existing or new test file. Ask scoping questions only when the
requested coverage depth can't be inferred.

## Feature Implementation Mode

When this skill is used as part of implementing a chart feature (e.g. after
`compose-to-chart` adds or updates a template), do not stop after planning:

1. Identify the affected chart under `charts/<chart>/...`.
2. Identify affected templates, `_helpers.tpl` entries, and `values.yaml` keys
   from the feature diff.
3. Read the existing test file for that template (or a sibling one) and mirror
   its style — see "Repo Conventions" below.
4. Add or update focused tests for the new or changed rendered behavior: enabled/
   disabled branches, value propagation, labels/selectors, secret encoding,
   env vars, and volume/persistence branches.
5. Run `make helm-unittest HELM_CHART=<chart-name>` and fix failures.

Ask the user only when there are multiple plausible feature semantics or the
chart/component can't be determined from local context.

## Repo Conventions

This repo is small (3 charts, all flat `templates/` directories — no
subdirectory components), so treat each chart as a single unit rather than
running the "simple vs. complex" split from larger multi-component charts.

- **Release name**: use `RELEASE-NAME` in assertions (helm-unittest's default),
  matching how `common`, `affine-helm`, and `patchmon-helm` tests already do it.
- **Namespace**: `common`'s templates set `metadata.namespace` explicitly
  (default renders as `NAMESPACE`); `affine-helm` and `patchmon-helm` templates
  do not set it at all — don't assert a namespace for those.
- **Secrets**: every chart resolves `CHANGE_ME`-default credentials through a
  `<chart>.<x>.<y>` helper (see `_helpers.tpl`) and base64-encodes them into a
  `Secret`. Test both the default (`CHANGE_ME`) and a custom value; compute the
  expected base64 with `printf '%s' "<value>" | base64` rather than guessing.
- **Persistence volumes**: `postgres.persistence.volume`,
  `redis.persistence.volume`, and (affine only) `persistence.config.volume` /
  `persistence.storage.volume` default to `{}` → renders `emptyDir: {}`. Test
  both the default and a custom volume source (e.g. an `nfs` block) to cover
  the `{{- if .Values.x.persistence.volume }}...{{- else }}emptyDir: {}{{- end }}`
  branch.
- **Conditional resources**: `ingress.enabled` (all charts, default `false`),
  `guacd.enabled` (patchmon-helm, default `true`), and
  `deploy.serviceAccount.create` (common, default `false`) gate whole documents.
  Always test both branches with `hasDocuments: { count: 0 }` for the disabled
  case.
- **Labels**: `affine-helm` and `patchmon-helm` labels come from
  `<chart>.labels` / `<chart>.selectorLabels`, called as
  `(dict "context" $ "name" "<component>" "component" "<role>")` — pass both
  when asserting the full label set, but remember `selectorLabels` only has
  `name` + `instance` (selectors are immutable, so never add chart-version keys
  there — see `compose-to-chart`'s `_helpers.tpl` section for why). `common`
  uses its own `common.labels.standard` / `common.labels.matchLabels` helpers
  instead (no per-component dict).
- **Ports**: `common`'s `deploy.containerPorts` / `service.ports` accept either
  a bare int or a `{port, protocol, targetPort}` map — test both forms in the
  same test case, and note that an empty `containerPorts: {}` renders
  `ports: null` (assert with `isNullOrEmpty`, not `notExists`).

## Discovery and Coverage Analysis

Work through these steps silently. Produce a single structured report at the end.

### 1. Understand the Chart Structure

- Read `charts/<chart>/Chart.yaml` for the chart version (labels embed
  `helm.sh/chart: <name>-<version>` — test assertions on the full label map
  must be updated when the chart version bumps).
- Read `charts/<chart>/values.yaml` for config axes and enable flags.
- List `charts/<chart>/templates/**` (excluding `_helpers.tpl`).
- Read `_helpers.tpl` before testing any template that calls its helpers.

### 2. Map Existing Test Coverage

- List `charts/<chart>/tests/**`. Each renderable template should have a
  `<template>_test.yaml` sibling (e.g. `server-deployment.yaml` →
  `server-deployment_test.yaml`).
- Check whether existing tests exercise the relevant branches (conditionals,
  both port/env forms, custom vs. default persistence), not just that a file
  exists.

### 3. Present the Coverage Report

```md
## <chart> - Test Coverage Analysis

| Template | Test file | Coverage |
|---|---|---|
| templates/server-deployment.yaml | tests/server-deployment_test.yaml | Good |
| templates/server-ingress.yaml | — | None |

### Notes
- <important observations about conditional rendering, secrets, or gotchas>

### Suggested starting point
<recommend the lowest-risk, highest-value template and explain why>
```

Wait for the user to choose before writing tests, unless this is feature
implementation mode (see above).

## helm-unittest Overview

Tests are YAML files in `charts/<chart-name>/tests/` that validate rendered
Kubernetes manifests. Each `tests[].it` case renders independently with that
case's value inputs. Keep tests focused: one behavior per test, explicit value
overrides via `set`, scoped assertions.

### Test File Structure

```yaml
# $schema: https://raw.githubusercontent.com/helm-unittest/helm-unittest/refs/heads/main/schema/helm-testsuite.json
suite: <descriptive suite name>
templates:
  - templates/<path-to-template>.yaml
tests:
  - it: <test case description>
    set:
      key.nested: value
    asserts:
      - isKind:
          of: Deployment
      - equal:
          path: metadata.name
          value: RELEASE-NAME-<chart-app>
```

### Assertion Guidance

| Assertion | Purpose |
|---|---|
| `equal` | Exact match at JSON path |
| `contains` / `notContains` | Array contains/lacks an exact element |
| `exists` / `notExists` | Path is present/absent |
| `isEmpty` / `isNotEmpty` | Path is empty or not |
| `isNullOrEmpty` / `isNotNullOrEmpty` | Path is null/empty, or present with content |
| `isKind` | Kubernetes resource kind check |
| `hasDocuments` | Number of YAML documents rendered (use `count: 0` for disabled conditionals) |
| `lengthEqual` | Array/map length equals expected count |
| `matchRegex` | Regex match on a string value (e.g. multi-line JSON `stringData`) |

Prefer `equal` and `contains` over broad `exists` checks — specific assertions
catch regressions. Use `notContains` / `notExists` for negative paths instead
of `not: true`.

### Path and jsonPath Guidance

When a map key contains dots or slashes (annotation/label keys), use bracket
syntax: `metadata.annotations["kubernetes.io/ingress.class"]`.

## Writing Workflow

1. Read the template being tested in full. Understand every conditional, value
   reference, and helper call.
2. Read `_helpers.tpl` for any helpers the template calls.
3. Read `values.yaml` for defaults and the full value schema.
4. Determine whether the template emits zero, one, or many documents (and
   under what condition).
5. Write tests for: default rendering, each significant conditional branch,
   custom values overriding key fields (image, secrets, persistence), and
   selector/label correctness.
6. Run the tests (see below) and fix failures by adjusting assertions to match
   actual rendered output — don't guess computed values (base64, JSON) by hand;
   derive them (`printf '%s' "<value>" | base64`) or render once with
   `helm template` and read the output.
7. Repeat until the test file passes.

## Running Tests

```bash
make helm-unittest                                    # every chart
make helm-unittest HELM_CHART=<chart-name>             # one chart
make helm-unittest HELM_CHART=<chart-name> \
  HELM_UNITTEST_FILE='tests/<file>_test.yaml'           # one file
```

`make test` runs `lint`, `template`, `validate` (kubeconform), and
`helm-unittest` together — the same checks CI runs.

## Rules

- Only create or edit `.yaml` files under `charts/*/tests/` when this skill is
  being used specifically to write tests.
- Do not modify templates, `values.yaml`, `Chart.yaml`, or non-test files as
  part of a test-writing task unless the user explicitly expands the scope. If
  writing a test reveals what looks like a real bug in a template (not just a
  quirk), report it to the user instead of silently "fixing" the assertion to
  hide it or silently patching the template.
- Never run destructive shell commands.
- Use `RELEASE-NAME` as the default release name in assertions.
- Always run `make helm-unittest HELM_CHART=<chart-name>` after writing tests.
- Test filenames must end with `.yaml`; `<template>_test.yaml` is preferred
  and mirrors the template it covers 1:1.
