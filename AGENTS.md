# AGENTS.md

This is a Helm charts repository containing application-specific and shared charts.

## Project Structure

```
helm-charts/
├── charts/
│   ├── firstdime-helm/  # Chart for First Dime personal finance application
│   ├── data-lab-helm/   # Shared infra for the Spark/Flink learning labs
│   ├── patchmon-helm/   # Chart for PatchMon application
│   ├── tompero-helm/    # Chart for Chez Tomperô recipe manager
│   ├── padel-score-helm/ # Chart for padel-score match scorer
│   ├── meiun-helm/      # Chart for meiun, the LLM-villager village sim
│   ├── eng-metrics-lab-helm/  # Chart for the eng-metrics-lab code-quality reporting stack
│   ├── ticket-live-event-scanner-helm/  # Chart for Ticket Live Event Scanner
│   └── common/          # Generic chart for multiple applications
└── .github/workflows/   # CI/CD pipelines
```

## Charts

### data-lab-helm
Shared infrastructure for the Spark and Flink learning labs (the exercise scripts live in the obsidian-vault repo). Includes:
- `spark` / `flink` namespaces, each with a ServiceAccount + scoped namespaced Role
- Single-node MinIO (Deployment + Service + PVC + Secret + bucket-creation hook Job), PVC-backed on the NFS StorageClass, reached over `s3a://` (datasets are seeded by the vault's exercise scripts, not this chart)

### firstdime-helm
Application-specific chart for deploying [First Dime](https://github.com/jfms7s/firstdime) (Number One Dime), a personal finance application. Includes:
- API server deployment + Service + Ingress
- Web UI frontend deployment + Service + Ingress
- Async worker deployment (scheduler, event relay)
- NATS JetStream message bus deployment + Service
- Optional Frankfurter exchange-rate API (Deployment + Service + PVC, off by default; the worker gets `FRANKFURTER_URL` when enabled)
- Optional bank-sync (Enable Banking client feeding `POST /imports`; Deployment + Service + Ingress + PVC, off by default; single replica, Recreate; metrics port never routed)
- Libsql (Turso) database integration
- File attachments shared storage
- Security hardening: non-root containers, read-only root filesystem, dropped capabilities

### patchmon-helm
Application-specific chart for deploying [PatchMon](https://patchmon.net/), a Linux patch management platform. Modeled on upstream's [docker-compose.yml](https://github.com/PatchMon/PatchMon/blob/main/docker/docker-compose.yml). Includes:
- PatchMon server deployment
- PostgreSQL database
- Redis cache
- guacd (in-browser RDP) sidecar
- Ingress configuration

### meiun-helm
Application-specific chart for deploying [meiun](https://github.com/jfms7s/meiun), a village sim with LLM-driven villagers. Includes:
- API deployment (Better Auth, tRPC, SSE; migrations on start) + Service
- Worker deployment (scheduler, minds queue, Web Push; single replica, Recreate) + metrics Service
- Web (static PWA on nginx-unprivileged) deployment + Service
- Optional pgvector Postgres (single replica, Recreate) with an optional chart-created PVC (kept on uninstall)
- One Ingress host, path-split: `/trpc` and `/api` to the API, `/` to the web app (one origin, no CORS)
- Optional ServiceMonitor for the API's and the worker's metrics ports (never routed by the Ingress)

### eng-metrics-lab-helm
Application-specific chart for deploying eng-metrics-lab, a code-quality reporting stack (`ghcr.io/jfms7s/quality-report`). Includes:
- Postgres (single replica, Recreate; PVC kept on uninstall; superuser password from an existing Secret)
- Argo CD PostSync migrate Job (schema and least-privilege roles)
- Nightly collector CronJob (GitHub artifacts into Postgres; `GITHUB_TOKEN` optional in the Secret)
- Weekly hotspots CronJob (churn × complexity per file; blob-less clones of `hotspots.repos` in a size-limited `/tmp`; rendered only when the list is set)
- Nightly backup CronJob (`pg_dump` to an NFS-backed PVC, old dumps pruned after `backup.keepDays`)
- Security hardening: non-root containers, dropped capabilities, read-only root filesystem on the collector, hotspots, migrate and backup pods

### tompero-helm
Application-specific chart for deploying [Chez Tomperô](https://github.com/jfms7s/tompero), a self-hosted recipe manager and meal planner. Includes:
- Server deployment (single replica, Recreate) + Service + optional Ingress
- `/data` volume for the SQLite database and images, with an optional chart-created PVC (kept on uninstall)
- Optional external Postgres via `server.databaseUrl` (EnvVarSource)

### padel-score-helm
Application-specific chart for deploying [padel-score](https://github.com/jfms7s/padel-score), a padel match scorer with live spectator links (SSE). Modeled on tompero-helm. Includes:
- Server deployment (single replica, Recreate; SQLite single writer) + Service + optional Ingress
- `/data` volume for the SQLite database, with an optional chart-created PVC (kept on uninstall)
- Public image, so no pull secret by default

### ticket-live-event-scanner-helm
Application-specific chart for deploying [Ticket Live Event Scanner](https://github.com/jfms7s/ticket-live-event-scanner), a scraper/notifier pipeline for ticketline.pt event listings. Modeled on upstream's own [deploy/k8s](https://github.com/jfms7s/ticket-live-event-scanner/tree/main/deploy/k8s) manifests. Includes:
- In-cluster NATS (JetStream) message bus
- Scraper CronJob (+ ServiceAccount/Role/RoleBinding)
- Telegram notifier deployment
- Email notifier deployment (calendar-invite emails on purchase)
- Web UI API deployment + Service
- Web UI frontend deployment + Service
- Ingress configuration

### common
Generic chart for one single-container application per release, consumed from helm-argo-cd. **Its scope is frozen** (see "Choosing a composition model"). Provides:
- One Deployment with one container (plus init containers, probes, update strategy and pod placement)
- One Service
- Optional Ingress
- Optional PersistentVolumeClaims
- ServiceAccount management

## Choosing a composition model

Owner decision, 2026-10-09:

- **One container, no chart-specific logic** -> a `common` release (configured from helm-argo-cd values). If it needs something outside `common`'s scope below, use bjw-s [`app-template`](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) (`oci://ghcr.io/bjw-s-labs/helm/app-template`) instead.
- **Several workloads, or render-time validation** (required-value guards, derived config) -> a bespoke `<app>-helm` chart in this repo.
- **A backing service used by one app** (database, broker, cache) -> either embedded in the app's chart behind `<svc>.enabled`, or a companion source next to the app in helm-argo-cd, with one rule repo-wide. Which of the two is that rule is not decided yet; the two existing sqld placements (embedded in `firstdime-helm`, a `common` companion source for the ticket scanner) stay as they are until it is. Moving a component between the two changes its Service DNS name and so its consumers' config.

**`common`'s scope is frozen** at a single-container Deployment + Service + optional Ingress + PVCs (+ ServiceAccount). It gets defect fixes only, no new controller features: no CronJob, StatefulSet, sidecar or second container, ConfigMap, ServiceMonitor, PodDisruptionBudget or `extraObjects`. The next app that needs one of those uses `app-template`. Existing `common` apps move to `app-template` only when they are next touched for another reason (an owner-run change in helm-argo-cd, one app at a time).

## Development Commands

```bash
# The gate: every check CI's lint-test job runs (helm lint, helm template,
# kubeconform, helm-unittest) on every chart under charts/. Paste its tail into PRs.
make test

# The same steps one at a time
make lint
make template
make validate                                    # kubeconform on the rendered manifests
make helm-unittest                               # every chart
make helm-unittest HELM_CHART=firstdime-helm     # one chart
make helm-unittest HELM_CHART=firstdime-helm HELM_UNITTEST_FILE=tests/api-deployment_test.yaml
make check-version                               # version-bump check CI runs on PRs

# By hand, one chart that renders on its defaults
helm lint charts/data-lab-helm
helm template my-release charts/data-lab-helm

# common, firstdime-helm, meiun-helm, padel-score-helm, patchmon-helm and
# ticket-live-event-scanner-helm refuse to render on their defaults by design (required image, credential and volume guards): pass
# their CI values
helm lint charts/firstdime-helm -f charts/firstdime-helm/ci/test-values.yaml
helm template my-release charts/firstdime-helm -f charts/firstdime-helm/ci/test-values.yaml
```

Without the `-f`, `helm lint` on those charts reports a misleading first error (`unable to parse YAML`): it treats the chart's `fail` as INFO and keeps rendering. The `make` targets already pass each chart's `ci/` values (see the per-chart cases in the `Makefile`).

See the [Makefile](Makefile) (`make help`) for the same checks CI runs, including `kubeconform` schema validation and `helm-unittest`. Use the `helm-chart-test` skill (`.claude/skills/helm-chart-test/SKILL.md`) to add or expand test coverage for a chart.

## Chart Versions

Any change to what a chart publishes (`templates/`, `values.yaml`, `Chart.yaml`, `README.md`, `.helmignore`, other chart files) needs a `version` bump in that chart's `Chart.yaml`: the release workflow uses chart-releaser with `skip_existing`, so an unbumped change is never published. Changes only under a chart's `tests/` or `ci/` need no bump.

`make check-version` (`scripts/check-version-bump.sh`, `BASE=origin/main` by default) fails naming each chart whose content changed without a higher version; the `lint-test` workflow runs it on every pull request. It is not part of `make test` because it needs a base ref.


Charts are released by the `release` job in `.github/workflows/lint-test.yml` ("Lint and Test Charts"). It runs only on a push to `main` and only after the `lint-test` job (lint, template, kubeconform, helm-unittest) passed in the same run. chart-releaser (`skip_existing: true`) then packages every chart whose `Chart.yaml` version has no GitHub Release yet, publishes it as a GitHub Release and adds it to the `gh-pages` `index.yaml`. A published version is permanent. Pull requests run `lint-test` (plus the version-bump check) and never the release job.

If CI cannot run (runner outage), re-run it and merge only once `lint-test` is green; never hand-publish to `gh-pages` or Releases. If a release job fails after merge, fix forward: the next green push to `main` publishes any version still missing.
