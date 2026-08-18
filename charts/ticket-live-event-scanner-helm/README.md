# ticket-live-event-scanner-helm

A Helm chart for deploying [Ticket Live Event Scanner](https://github.com/jfms7s/ticket-live-event-scanner),
a scraper/notifier pipeline that watches ticketline.pt event listings and
pushes Telegram alerts, along with its in-cluster NATS (JetStream) message
bus. Modeled on upstream's own
[deploy/k8s](https://github.com/jfms7s/ticket-live-event-scanner/tree/main/deploy/k8s)
manifests.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A [Turso](https://turso.tech/) (libSQL) database and a Telegram bot,
  credentials for both supplied by the caller (see Secrets below)

## Installing the Chart

```bash
helm install my-release .
```

Set `turso.databaseUrl.value`, `turso.authToken.value`, `telegram.botToken.value`,
and `telegram.chatId.value` (or the matching `.valueFrom`) explicitly before
installing — see the note below.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nats.image.*` | NATS image | `nats:2-alpine` |
| `nats.resources` | NATS container resources | `requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 500m, memory: 512Mi}` |
| `nats.persistence.volume` | Volume source (excl. `name`) for NATS JetStream file storage | `{}` (emptyDir) |
| `turso.databaseUrl` / `turso.authToken` | Turso credentials shared by the scraper and web-ui-api, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `telegram.botToken` / `telegram.chatId` | Telegram bot credentials for telegram-notifier, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `scraper.image.*` | Scraper image | `ghcr.io/jfms7s/ticket-live-event-scanner-scraper:latest` |
| `scraper.schedule` | CronJob schedule for the scraper | `0 * * * *` (hourly) |
| `scraper.backoffLimit` | CronJob `backoffLimit` | `2` |
| `scraper.hubPages` | Comma-separated ticketline.pt hub page slugs to re-check for new session IDs | `auchan-live-academia-maia-98164,auchan-live-academia-aveiro-98167` |
| `scraper.userAgent` | HTTP User-Agent sent by the scraper | `ticket-live-event-scanner/0.1 (personal project; contact: jfms7s@gmail.com)` |
| `scraper.requestDelayMs` | Delay between scrape requests, in milliseconds | `1500` |
| `scraper.resources` | Scraper container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `telegramNotifier.image.*` | Telegram notifier image | `ghcr.io/jfms7s/ticket-live-event-scanner-telegram-notifier:latest` |
| `telegramNotifier.resources` | Telegram notifier container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `webUiApi.image.*` | Web UI API image | `ghcr.io/jfms7s/ticket-live-event-scanner-web-ui-api:latest` |
| `webUiApi.corsOrigin` | Allowed frontend origin(s) for the API | `*` |
| `webUiApi.resources` | Web UI API container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `webUiFrontend.image.*` | Web UI frontend image | `ghcr.io/jfms7s/ticket-live-event-scanner-web-ui-frontend:latest` |
| `webUiFrontend.replicas` | Web UI frontend replica count | `1` |
| `webUiFrontend.resources` | Web UI frontend container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the web UI frontend | disabled |

### Secrets

Argo CD does not support Helm's `lookup` function, so this chart can't
safely auto-generate random secrets and persist them across syncs the way a
plain `helm install` could — they would silently rotate on the next sync.
`turso.databaseUrl`, `turso.authToken`, `telegram.botToken`, and
`telegram.chatId` are each a standard Kubernetes `EnvVarSource` (the same
shape as a container's `env[].valueFrom`): set `<field>.value` to a plain
literal, e.g. from a secrets file kept out of version control, or
`<field>.valueFrom` (e.g. a `secretKeyRef`) to source it from a Secret you
manage yourself instead (an external secrets manager, ...). `valueFrom`
takes precedence whenever it's set, and each field toggles independently:

```yaml
turso:
  authToken:
    valueFrom:
      secretKeyRef:
        name: turso-credentials
        key: auth_token
```

### Persistent storage

NATS doesn't ship a default storage backend for its JetStream data, since
the right one (NFS, hostPath, a PVC, cloud block storage, ...) is
environment-specific. `nats.persistence.volume` takes the full body of a
Kubernetes volume source (everything except `name`), e.g.:

```yaml
nats:
  persistence:
    volume:
      nfs:
        server: 192.168.1.10
        path: /volumes/ticket-scanner/nats
```

Leaving it unset falls back to `emptyDir` (non-persistent) — fine for a
quick test, not for real data (JetStream state, and therefore in-flight
event dedup, is lost on pod restart).

### web-ui-api replica count

`webUiApi` is intentionally hardcoded to 1 replica in the template (not
configurable via `values.yaml`): multiple replicas would consume the same
JetStream consumer group and duplicate rows in Turso. Use a
PodDisruptionBudget if you need stronger availability guarantees instead of
scaling out.

## Deployment

This chart creates: a Deployment + Service for NATS, a CronJob (+
ServiceAccount/Role/RoleBinding) for the scraper, a Deployment for
telegram-notifier, a Deployment + Service for web-ui-api, and a Deployment +
Service (+ optional Ingress) for web-ui-frontend.

## Uninstalling

```bash
helm uninstall my-release
```
