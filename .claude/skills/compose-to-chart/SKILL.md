---
name: compose-to-chart
description: Create a new Helm chart in this repo from an application's docker-compose.yml, or update an existing chart when upstream's compose file changes. Use when the user says "build/create a chart for <repo>", "same as affine/patchmon, build a chart for X", or "update the <x>-helm chart from upstream".
user-invocable: true
---

# compose-to-chart

Converts a `docker-compose.yml` (usually from an upstream project's repo)
into a Helm chart under `charts/<app>-helm/` that matches the conventions
already established by `charts/affine-helm` and `charts/patchmon-helm`, or
updates an existing chart when upstream's compose file has drifted. Read
both of those charts first if this is your first time using this skill —
they are the canonical reference, more authoritative than any summary here.

$ARGUMENTS is either a path/URL to a `docker-compose.yml` (create mode) or
the name of an existing `charts/*-helm` directory to refresh (update mode).
If ambiguous, ask.

## Inputs to gather before writing anything

1. The compose file itself (`docker/docker-compose.yml`, `docker-compose.yml`,
   etc. — check both locations). Fetch it with WebFetch/curl if given a repo
   URL rather than a local path.
2. Any referenced `.env` / `env.example` file — compose files almost always
   reference env vars (`${POSTGRES_PASSWORD}`, `env_file: .env`) that only
   this file documents. Read it; it tells you which env vars are required
   vs. optional-with-defaults, and which are secrets.
3. If updating an existing chart: read the chart's current `Chart.yaml`,
   `values.yaml`, and `templates/*` in full before touching anything, so
   changes are additive/corrective rather than a rewrite.

## Chart layout and naming

- Chart directory: `charts/<app>-helm/` (e.g. `patchmon-helm`).
- `Chart.yaml`: `apiVersion: v2`, `type: application`, start new charts at
  `version: 0.1.0`, `sources:` listing both the upstream repo and
  `https://github.com/jfms7s/helm-charts`, `maintainers:` with the existing
  `jfms7s` entry — copy the shape from `charts/patchmon-helm/Chart.yaml`.
- One template file per resource, named `<component>-<kind>.yaml` (e.g.
  `server-deployment.yaml`, `postgres-secret.yaml`, `guacd-service.yaml`),
  not one giant file. The primary app service is conventionally named
  `server` (see patchmon-helm) unless upstream's own compose service name
  is clearer.
- All resource names in templates: `{{ .Release.Name }}-<chart-app>-<component>`
  (e.g. `{{ .Release.Name }}-patchmon-postgres`), so multiple releases of the
  same chart don't collide.

## `_helpers.tpl` — copy this pattern verbatim, renaming the prefix

Every chart in this repo defines the same three helpers, prefixed with the
chart name (`affine-helm.*`, `patchmon-helm.*`). Copy
`charts/patchmon-helm/templates/_helpers.tpl` and rename:

- `<chart>.chart` — the `helm.sh/chart` label value.
- `<chart>.labels` — takes `(dict "context" $ "name" "<component>" "component" "<role>")`.
  Include `app.kubernetes.io/part-of: <app>` (the base app name, not the
  chart name).
- `<chart>.selectorLabels` — **only** `name` + `instance`. Never add
  chart-version-derived keys here: Deployment `matchLabels` and Service
  `selector` are immutable after creation, so a version bump in the full
  label set would break `helm upgrade` if selectors used it too.

For every secret-backed value (passwords, tokens, keys), add a resolver
helper (`<chart>.postgres.password`, `<chart>.server.jwtSecret`, ...) that
does `{{ .Values.x.y | default "CHANGE_ME" }}` — see "Secrets" below for why.

## Translating compose services

Go service-by-service. For each one, decide: does it need persistent state
(→ Deployment + Service, `strategy: Recreate` if it owns a volume) or is it
stateless (→ Deployment + Service, default `RollingUpdate`)? This repo never
uses StatefulSets even for the databases — matches how affine-helm and
patchmon-helm already do it, keep it consistent.

| Compose concept | Helm/K8s translation |
|---|---|
| `image:` | `values.yaml`: `<component>.image.{repository,tag,pullPolicy}`, default `pullPolicy: IfNotPresent` |
| `ports:` (published) | Service `port`/`targetPort`; container `ports[].containerPort` |
| `environment:` / `env_file` | Deployment `env:` entries. Plain config → `value:`. Secrets → `valueFrom.secretKeyRef` (see below) |
| `command:` referencing `${VAR}` | Container `command:` using k8s substitution syntax `$(VAR)` where `VAR` is one of that container's own `env:` entries |
| `depends_on: condition: service_healthy` | Not directly portable — express the same ordering guarantee via that dependency's own liveness/readiness probes; don't add init containers unless the app truly crash-loops without one |
| `healthcheck.test: ["CMD", "pg_isready", ...]` | `exec` probe running the same command. `CMD-SHELL "a && b"` → `["sh", "-c", "a && b"]` |
| `healthcheck.interval/timeout/retries` | `periodSeconds` / `timeoutSeconds` / `failureThreshold`. If probe needs a container env var (e.g. a password), it's available — exec probes run inside the container's own environment |
| `volumes:` (named volume) | `values.yaml`: `<component>.persistence.volume: {}`; template does `{{- if .Values.x.persistence.volume }}{{ toYaml ... }}{{- else }}emptyDir: {}{{- end }}`. Never default to a specific storage class — see affine-helm's README note on why |
| `restart: unless-stopped` | Deployment pod spec `restartPolicy: Always` (the only legal value for a Deployment anyway) |
| `read_only: true` | container `securityContext.readOnlyRootFilesystem: true` |
| `tmpfs: [/path:size=Nm]` | a `volumes: [{name, emptyDir: {medium: Memory, sizeLimit: Nm}}]` mounted at that path |
| `security_opt: [no-new-privileges:true]` | `securityContext.allowPrivilegeEscalation: false` |
| `cap_drop: [ALL]` | `securityContext.capabilities.drop: [ALL]` |
| `mem_limit` / `cpus` | `resources.limits.memory` / `resources.limits.cpu` |
| `networks:` | drop entirely — in-cluster Service DNS (`<component>` or `{{ .Release.Name }}-<app>-<component>`) replaces compose's network aliasing |
| `logging:` | drop — cluster-level log collection is out of scope for the chart |

## Secrets

**Never auto-generate a password/token in a template.** Argo CD does not
support Helm's `lookup` function, so a chart can't safely generate a random
value once and have it persist across syncs — every sync would silently
rotate it, breaking auth or losing data. Every credential (DB password,
cache password, JWT/session secrets, encryption keys, ...) must:

1. Have a values.yaml key defaulting to the literal string `"CHANGE_ME"`,
   with a comment explaining the Argo CD constraint (copy the wording from
   `values.yaml` in either existing chart) and, if upstream's env.example
   suggests a generation command (e.g. `openssl rand -hex 64`), include it.
2. Get a `<chart>.<x>.<y>` helper in `_helpers.tpl` that resolves it with
   `| default "CHANGE_ME"`.
3. Be rendered into a `Secret` (`type: Opaque`, `data:` with `| b64enc`),
   never inlined as plaintext `env.value` in a Deployment.
4. Be documented in the chart README's "Secrets" section, listed alongside
   every other credential the caller must override before installing.

## Ingress, resources, securityContext (top-level)

Copy the top-level `ingress:` block shape verbatim from `values.yaml` in
either existing chart (`enabled`/`className`/`annotations`/`hosts`/`tls`),
and the corresponding `*-ingress.yaml` template — only the backend service
name and default port change. Same for the top-level `resources: {}`,
`securityContext: {}`, `podSecurityContext: {}` on the main app component —
empty by default, commented-out examples in values.yaml, so the caller opts
in rather than the chart imposing limits nobody asked for.

## Chart README.md

Mirror `charts/patchmon-helm/README.md`'s structure: prereqs, install
command, a full parameter table (one row per `values.yaml` leaf, defaults
matching exactly), then prose sections for anything non-obvious — secrets
and the Argo CD caveat, persistence and the volume-source shape, any
security hardening inherited from compose (like patchmon's guacd), and
"Deployment" (what resources get created) / "Uninstalling".

## Registering the chart in the repo

After the chart itself is written, wire it into the repo the same way for
every chart — grep each of these files for an existing chart name and add
the new one alongside it, don't restructure:

1. `AGENTS.md` — project structure tree, and a `### <app>-helm` subsection
   under "Charts" describing what it deploys.
2. `README.md` (repo root) — an entry under "Available Charts" linking to
   the chart's own README.
3. `.github/workflows/lint-test.yml` — add one line each to the "Lint Helm
   charts", "Template Helm charts", "Validate rendered templates", and
   "Run helm-unittest" steps.
4. `Makefile` — nothing to do; its targets glob `charts/*` automatically.
5. `charts/<app>-helm/tests/` — use the `helm-chart-test` skill to add
   helm-unittest coverage for the new or changed templates before calling the
   chart done.

## Validation — do not skip, do not hand-wave

Run the exact same checks CI runs, locally, before calling the work done:

```bash
make test          # lint + template + kubeconform + helm-unittest for every chart
```

This downloads `kubeconform` to `.bin/` on first run (same binary CI fetches
from `yannh/kubeconform` releases), installs the `helm-unittest` plugin if
missing, and runs `helm lint`, `helm template`, schema validation, and any
`charts/*/tests/**` helm-unittest suites. Fix every failure — a chart that
fails `make test` locally will fail CI. If you
changed `values.yaml` defaults in a way that makes the chart un-installable
without overrides (e.g. a `CHANGE_ME` password), that's expected and
`kubeconform` still passes since it only validates schema shape, not values
policy — don't try to "fix" that by inventing a fake default.

If `helm` or the downloaded `kubeconform` binary isn't on PATH, `make test`
still works — it only shells out to `helm` (must be pre-installed) and
manages `kubeconform` itself.

## Update mode

When refreshing an existing chart from a newer upstream compose file, diff
service-by-service against the chart's current templates: new services,
removed services, changed images/ports/env vars/healthchecks, new
security/resource constraints. Prefer minimal, targeted edits over
regenerating files from scratch — preserve existing `values.yaml` defaults
and any repo-specific comments unless upstream's change actually
invalidates them. Bump the chart's `version` in `Chart.yaml` (patch bump for
a values/template fix, minor for new components) — `appVersion` should track
upstream's image tag if the chart pins one. Re-run `make test` afterward.
