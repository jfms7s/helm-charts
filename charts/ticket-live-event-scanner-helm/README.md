# ticket-live-event-scanner-helm

A Helm chart for deploying [Ticket Live Event Scanner](https://github.com/jfms7s/ticket-live-event-scanner),
a scraper/notifier pipeline that watches ticketline.pt event listings, pushes
Telegram alerts, and emails a calendar invite (.ics) when an event is marked
purchased. Everything runs in one pod (web-ui-api) on one SQLite file; there is no message broker. Modeled on
upstream's own
[deploy/k8s](https://github.com/jfms7s/ticket-live-event-scanner/tree/master/deploy/k8s)
manifests.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A [Turso](https://turso.tech/) (libSQL) database, a Telegram bot, and an
  SMTP relay (e.g. Gmail with an App Password), credentials for all three
  supplied by the caller (see Secrets below)

## Installing the Chart

```bash
helm install my-release .
```

Set `turso.databaseUrl`, `turso.authToken`, `telegram.botToken`,
`telegram.chatId`, `smtp.username` and `smtp.password` (each as `.value` or
`.valueFrom`), plus `smtp.from` and `smtp.to`, before installing. The chart
refuses to render while any of them is empty or the `CHANGE_ME` placeholder
without a `valueFrom` (since 0.7.0); see the note below.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `database.sqlite.enabled` | Keep the database in a SQLite file (WAL) on a volume instead of the libSQL server (app >= v0.12.0); one replica owns it, so the Deployment becomes `Recreate` | `false` |
| `database.sqlite.importFromSqld` | While true, a new SQLite file is filled once from the libSQL server named by `turso.*`, verified, and the process does not start if the copy fails. Set false after the first start: the `turso.*` settings then leave the Deployment and are no longer required (with them set, a lost volume would copy the server's frozen snapshot over newer state) | `true` |
| `database.sqlite.allowEmpty` | Start on an empty database with nothing to import (a fresh install); without it an empty file is refused | `false` |
| `database.sqlite.path` | The file inside the container; its directory is the mount point | `/data/ticket-scanner.db` |
| `database.sqlite.claim.storageClassName` / `.size` | Have the chart create the PVC `<release>-ticket-scanner-web-ui-api-data` (kept on uninstall/prune) | unset |
| `database.sqlite.existingClaim` | Use a PVC you manage instead | `""` |
| `turso.databaseUrl` / `turso.authToken` | Turso credentials for web-ui-api, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `telegram.botToken` / `telegram.chatId` | Telegram bot credentials for web-ui-api's Telegram channel, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `scraper.hubPages` | Comma-separated ticketline.pt hub page slugs or URLs; seeds the watches table (manage them on the dashboard's Watches page afterwards) | `auchan-live-academia-maia-98164,auchan-live-academia-aveiro-98167` |
| `scraper.userAgent` | HTTP User-Agent sent by the scraper; add your own contact to it | `ticket-live-event-scanner (+https://github.com/jfms7s/ticket-live-event-scanner)` |
| `scraper.requestDelayMs` | Delay between scrape requests, in milliseconds | `1500` |
| `scraper.enabled` | Run the scraper (a scrape at start-up and every hour) and the weekly digest (Sunday 19:00 Europe/Lisbon) inside web-ui-api (app >= v0.11.0); `false` sets `SCRAPER_ENABLED=false` | `true` |
| `smtp.host` / `smtp.port` | SMTP relay address for web-ui-api's email channel | `smtp.gmail.com` / `587` |
| `smtp.username` / `smtp.password` | SMTP auth credentials, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `smtp.from` / `smtp.to` | From address and comma-separated recipient list for the calendar-invite email | `CHANGE_ME` |
| `webUiApi.image.*` | Web UI API image | `ghcr.io/jfms7s/ticket-live-event-scanner-web-ui-api:latest` |
| `webUiApi.corsOrigin` | `CORS_ORIGIN`, only for a dashboard served from another origin (dev). Empty: no CORS headers (web-ui-api serves the dashboard itself) | `""` |
| `webUiApi.metrics.serviceMonitor.enabled` / `.interval` / `.labels` | ServiceMonitor for web-ui-api's `/metrics` (scraper run health, app >= v0.6.0); needs the Prometheus Operator CRDs. The alert rules belong with your Prometheus | `false` / `60s` / `{}` |
| `webUiApi.resources` | Web UI API container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the web UI (web-ui-api serves the dashboard at `/` and the API under `/api`); a path's `service` routes it to another Service instead, always on that Service's port named `http` (a path's `port` key is ignored) | disabled |

### Secrets

Argo CD does not support Helm's `lookup` function, so this chart can't
safely auto-generate random secrets and persist them across syncs the way a
plain `helm install` could — they would silently rotate on the next sync.
`turso.databaseUrl`, `turso.authToken`, `telegram.botToken`,
`telegram.chatId`, `smtp.username`, and `smtp.password` are each a standard Kubernetes `EnvVarSource` (the same
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

A credential given as `value` is stored in a chart-owned Secret,
`<release>-ticket-scanner-credentials` (one key per credential, e.g. `TURSO_AUTH_TOKEN`), and the
containers read it through `secretKeyRef`, so it never appears in a
Deployment or CronJob spec. The Secret is rendered only while at least one
credential uses `value`. A pod that reads one carries a
`checksum/credentials` annotation (sha256 of just the credentials it reads),
so changing a `value` rolls only the pods that use it. The hash is unsalted
and readable with the workload, so give `value` credentials high entropy, or
use `valueFrom`.

### web-ui-api replica count

`webUiApi` is hardcoded to 1 replica (and `Recreate`) because it owns one SQLite file on a ReadWriteOnce volume.

## Security

web-ui-api has no authentication, and some of its calls have side effects
(marking an event purchased sends email and calendar invites). With the
ingress off it is reachable only in-cluster. Turning the ingress on
publishes the dashboard and the API (same origin, app >= v0.7.0) to anyone
who can reach that host, so protect it there, e.g. with a Traefik forward-auth
or basic-auth middleware:

```yaml
ingress:
  annotations:
    traefik.ingress.kubernetes.io/router.middlewares: <namespace>-<middleware>@kubernetescrd
```

Mutating calls need an `X-Requested-With` header, so other sites cannot
trigger them from a visitor's browser; that is not authentication and does
not stop direct requests. No CORS headers are sent unless
`webUiApi.corsOrigin` is set.

## Deployment

This chart creates: a Deployment + Service (+ optional Ingress) for web-ui-api, which serves the dashboard, scrapes and sends the weekly digest, and delivers the Telegram and email notifications from a database outbox (app >= v0.14.0), plus its SQLite volume and an optional ServiceMonitor (`webUiApi.metrics.serviceMonitor.enabled`).

Every pod runs as uid/gid 1000 (`fsGroup` 1000) with the `RuntimeDefault`
seccomp profile and no service account token; every container has a
read-only root filesystem, no capabilities, no privilege escalation and a
`/tmp` emptyDir.

## Uninstalling

```bash
helm uninstall my-release
```

## Upgrading to 0.15.0

The NATS broker is gone (needs app >= v0.15.0, which no longer connects to it). The `nats.*` and `networkPolicy.*` values are removed; remove them from your values. A sync that prunes the old objects also deletes the NATS volume claim, so move to this version only after app v0.14.0 or later has been delivering from the outbox for a day.
