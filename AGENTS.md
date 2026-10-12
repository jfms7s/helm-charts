# AGENTS.md

This is a Helm charts repository containing application-specific and shared charts.

## Project Structure

```
helm-charts/
├── charts/
│   ├── affine-helm/     # Chart for Affine application
│   ├── firstdime-helm/  # Chart for First Dime personal finance application
│   ├── data-lab-helm/   # Shared infra for the Spark/Flink learning labs
│   ├── patchmon-helm/   # Chart for PatchMon application
│   ├── tompero-helm/    # Chart for Chez Tomperô recipe manager
│   ├── ticket-live-event-scanner-helm/  # Chart for Ticket Live Event Scanner
│   └── common/          # Generic chart for multiple applications
└── .github/workflows/   # CI/CD pipelines
```

## Charts

### data-lab-helm
Shared infrastructure for the Spark and Flink learning labs (the exercise scripts live in the obsidian-vault repo). Includes:
- `spark` / `flink` namespaces, each with a ServiceAccount + scoped namespaced Role
- Single-node MinIO (Deployment + Service + PVC + Secret + bucket-creation hook Job), PVC-backed on the NFS StorageClass, reached over `s3a://` (datasets are seeded by the vault's exercise scripts, not this chart)

### affine-helm
Application-specific chart for deploying the [Affine](https://affine.pro/) workspace application. Includes:
- Affine main deployment
- PostgreSQL database
- Redis cache
- Ingress configuration
- Migration job

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

### tompero-helm
Application-specific chart for deploying [Chez Tomperô](https://github.com/jfms7s/tompero), a self-hosted recipe manager and meal planner. Includes:
- Server deployment (single replica, Recreate) + Service + optional Ingress
- `/data` volume for the SQLite database and images, with an optional chart-created PVC (kept on uninstall)
- Optional external Postgres via `server.databaseUrl` (EnvVarSource)

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
Reusable chart for deploying containerized applications. Provides:
- Deployment template
- Service configuration
- Ingress support
- ServiceAccount management

## Development Commands

```bash
# Lint a chart
helm lint charts/affine-helm
helm lint charts/firstdime-helm
helm lint charts/patchmon-helm
helm lint charts/common

# Template a chart
helm template my-release charts/affine-helm
helm template my-release charts/firstdime-helm
helm template my-release charts/patchmon-helm
helm template my-release charts/common

# Package a chart
helm package charts/affine-helm
helm package charts/firstdime-helm
helm package charts/patchmon-helm
helm package charts/common

# Run helm-unittest tests (rendered-manifest assertions, see charts/*/tests/)
make helm-unittest
make helm-unittest HELM_CHART=firstdime-helm
```

See the [Makefile](Makefile) (`make help`) for the same checks CI runs, including `kubeconform` schema validation and `helm-unittest`. Use the `helm-chart-test` skill (`.claude/skills/helm-chart-test/SKILL.md`) to add or expand test coverage for a chart.

## Release Process

Charts are automatically released via GitHub Actions when version tags are pushed.
