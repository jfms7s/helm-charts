# AGENTS.md

This is a Helm charts repository containing application-specific and shared charts.

## Project Structure

```
helm-charts/
├── charts/
│   ├── affine-helm/     # Chart for Affine application
│   ├── patchmon-helm/   # Chart for PatchMon application
│   ├── ticket-live-event-scanner-helm/  # Chart for Ticket Live Event Scanner
│   └── common/          # Generic chart for multiple applications
└── .github/workflows/   # CI/CD pipelines
```

## Charts

### affine-helm
Application-specific chart for deploying the [Affine](https://affine.pro/) workspace application. Includes:
- Affine main deployment
- PostgreSQL database
- Redis cache
- Ingress configuration
- Migration job

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
helm lint charts/patchmon-helm
helm lint charts/common

# Template a chart
helm template my-release charts/affine-helm
helm template my-release charts/patchmon-helm
helm template my-release charts/common

# Package a chart
helm package charts/affine-helm
helm package charts/patchmon-helm
helm package charts/common

# Run helm-unittest tests (rendered-manifest assertions, see charts/*/tests/)
make helm-unittest
make helm-unittest HELM_CHART=affine-helm
```

See the [Makefile](Makefile) (`make help`) for the same checks CI runs, including `kubeconform` schema validation and `helm-unittest`. Use the `helm-chart-test` skill (`.claude/skills/helm-chart-test/SKILL.md`) to add or expand test coverage for a chart.

## Release Process

Charts are automatically released via GitHub Actions when version tags are pushed.
