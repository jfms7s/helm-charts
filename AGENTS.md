# AGENTS.md

This is a Helm charts repository containing application-specific and shared charts.

## Project Structure

```
helm-charts/
├── charts/
│   ├── affine-helm/     # Chart for Affine application
│   ├── budget-manager-helm/  # Chart for Budget Manager personal finance application
│   ├── data-lab-helm/   # Shared infra for the Spark/Flink learning labs
│   ├── patchmon-helm/   # Chart for PatchMon application
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

### budget-manager-helm
Application-specific chart for deploying [Budget Manager](https://github.com/jfms7s/budget-manager), a personal finance application. Includes:
- API server deployment + Service + Ingress
- Web UI frontend deployment + Service + Ingress
- Async worker deployment (scheduler, event relay)
- NATS JetStream message bus deployment + Service
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
helm lint charts/budget-manager-helm
helm lint charts/patchmon-helm
helm lint charts/common

# Template a chart
helm template my-release charts/affine-helm
helm template my-release charts/budget-manager-helm
helm template my-release charts/patchmon-helm
helm template my-release charts/common

# Package a chart
helm package charts/affine-helm
helm package charts/budget-manager-helm
helm package charts/patchmon-helm
helm package charts/common

# Run helm-unittest tests (rendered-manifest assertions, see charts/*/tests/)
make helm-unittest
make helm-unittest HELM_CHART=budget-manager-helm
```

See the [Makefile](Makefile) (`make help`) for the same checks CI runs, including `kubeconform` schema validation and `helm-unittest`. Use the `helm-chart-test` skill (`.claude/skills/helm-chart-test/SKILL.md`) to add or expand test coverage for a chart.

## Release Process

Charts are automatically released via GitHub Actions when version tags are pushed.
