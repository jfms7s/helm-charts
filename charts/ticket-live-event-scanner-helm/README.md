# ticket-live-event-scanner-helm

A Helm chart for deploying [Ticket Live Event Scanner](https://github.com/jfms7s/ticket-live-event-scanner),
a scraper/notifier pipeline that watches ticketline.pt event listings, pushes
Telegram alerts, and emails a calendar invite (.ics) when an event is marked
purchased, along with its in-cluster NATS (JetStream) message bus. Modeled on
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
| `nats.image.*` | NATS image | `nats:2-alpine` |
| `nats.resources` | NATS container resources | `requests: {cpu: 100m, memory: 128Mi}, limits: {cpu: 500m, memory: 512Mi}` |
| `nats.persistence.volume` | Volume source (excl. `name`) for NATS JetStream file storage | `{}` (emptyDir) |
| `nats.persistence.claim` | `{storageClassName, size}`: when the class is set, render a PVC `<release>-ticket-scanner-nats-data` (RWO, kept on uninstall/prune); point `nats.persistence.volume` at it via `persistentVolumeClaim.claimName` | unset |
| `nats.persistence.subPath` | Subdirectory of the volume to mount as `/data` (use on block-backed PVCs to keep ext4's `lost+found` out of it) | `""` |
| `nats.auth.token` | `{value, valueFrom}`: shared token the broker requires from every client (see [NATS authentication](#nats-authentication)). Empty = no auth | `{value: "", valueFrom: {}}` |
| `networkPolicy.enabled` | Render a NetworkPolicy limiting ingress to the NATS pod to TCP 4222 from this release's scraper, notifiers and web-ui-api | `false` |
| `turso.databaseUrl` / `turso.authToken` | Turso credentials shared by the scraper and web-ui-api, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `telegram.botToken` / `telegram.chatId` | Telegram bot credentials for telegram-notifier, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `scraper.image.*` | Scraper image | `ghcr.io/jfms7s/ticket-live-event-scanner-scraper:latest` |
| `scraper.schedule` | CronJob schedule for the scraper | `0 * * * *` (hourly) |
| `scraper.backoffLimit` | CronJob `backoffLimit` | `2` |
| `scraper.ttlSecondsAfterFinished` | Seconds a finished scraper Job is kept before deletion | `86400` |
| `scraper.hubPages` | Comma-separated ticketline.pt hub page slugs to re-check for new session IDs | `auchan-live-academia-maia-98164,auchan-live-academia-aveiro-98167` |
| `scraper.userAgent` | HTTP User-Agent sent by the scraper; add your own contact to it | `ticket-live-event-scanner (+https://github.com/jfms7s/ticket-live-event-scanner)` |
| `scraper.requestDelayMs` | Delay between scrape requests, in milliseconds | `1500` |
| `scraper.digest.enabled` | Weekly Telegram digest CronJob (`scraper --digest`, app >= v0.6.0): one summary to the chat; never retried | `false` |
| `scraper.digest.schedule` / `scraper.digest.timeZone` | Digest schedule and its IANA time zone (`spec.timeZone`) | `0 19 * * 0` / `Europe/Lisbon` (Sunday 19:00) |
| `scraper.resources` | Scraper container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `telegramNotifier.image.*` | Telegram notifier image | `ghcr.io/jfms7s/ticket-live-event-scanner-telegram-notifier:latest` |
| `telegramNotifier.resources` | Telegram notifier container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
| `smtp.host` / `smtp.port` | SMTP relay address for email-notifier | `smtp.gmail.com` / `587` |
| `smtp.username` / `smtp.password` | SMTP auth credentials, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `smtp.from` / `smtp.to` | From address and comma-separated recipient list for the calendar-invite email | `CHANGE_ME` |
| `emailNotifier.image.*` | Email notifier image | `ghcr.io/jfms7s/ticket-live-event-scanner-email-notifier:latest` |
| `emailNotifier.resources` | Email notifier container resources | `requests: {cpu: 50m, memory: 64Mi}, limits: {cpu: 200m, memory: 128Mi}` |
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

### NATS authentication

The broker accepts anonymous clients unless `nats.auth.token` is set
(same `{value, valueFrom}` shape as the credentials above). When it is,
the chart renders a ConfigMap `<release>-ticket-scanner-nats-config` with
`authorization { token: $NATS_TOKEN_QUOTED }` and starts NATS with
`-c /etc/nats/nats.conf`; the broker reads the token from its environment,
so it is never in the ConfigMap or on the command line. Every client
(scraper, notifiers, web-ui-api) gets `NATS_TOKEN` from the same source.
App images before `v0.5.0` ignore `NATS_TOKEN` and are refused, so bump the
images first. A `value` token with `"`, `\` or a newline fails the render; a
`valueFrom` one with any of them would stop the broker at startup.

```yaml
nats:
  auth:
    token:
      valueFrom:
        secretKeyRef:
          name: ticket-scanner-nats
          key: NATS_TOKEN
```

Turning it on (or rotating a `value` token) restarts the broker and every
client in the same sync; clients reconnect once the broker is back. A
`valueFrom` token rotated in its Secret rolls nothing: restart the broker
and then the notifiers and web-ui-api (`kubectl rollout restart`); the
scraper CronJob reads the new token on its next run. The chart cannot check
the image versions, so make sure every app image is `v0.5.0` or later
before turning auth on. The token must not contain `"`, `\` or a newline.

### NetworkPolicy

`networkPolicy.enabled: true` adds `<release>-ticket-scanner-nats`, which
allows ingress to the NATS pod only on TCP 4222 and only from pods of this
release labelled `app.kubernetes.io/name` `scraper`, `telegram-notifier`,
`email-notifier` or `web-ui-api`. Egress is not restricted, and the other
workloads get no policy. It needs a CNI that enforces NetworkPolicy (k3s's
embedded kube-router does).

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

`webUiApi` is hardcoded to 1 replica in the template (not configurable via
`values.yaml`) because multi-replica operation is untested. Its JetStream
consumers are durable pull consumers with explicit ack, so two pods (as
during a rolling update) split the messages between them rather than both
processing each one; a message redelivered after its ack wait is recorded
once per delivery sequence.

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

This chart creates: a Deployment + Service for NATS, a CronJob (+
ServiceAccount/Role/RoleBinding) for the scraper, a Deployment for
telegram-notifier, a Deployment for email-notifier, a Deployment + Service
(+ optional Ingress) for web-ui-api, which also serves the dashboard; optionally a NATS ConfigMap (`nats.auth.token`) and a NATS
NetworkPolicy (`networkPolicy.enabled`), a weekly digest CronJob
(`scraper.digest.enabled`) and a ServiceMonitor for web-ui-api
(`webUiApi.metrics.serviceMonitor.enabled`).

Every pod runs as uid/gid 1000 (`fsGroup` 1000) with the `RuntimeDefault`
seccomp profile and no service account token; every container has a
read-only root filesystem, no capabilities, no privilege escalation and a
`/tmp` emptyDir (the notifiers' health file lives there).

## Uninstalling

```bash
helm uninstall my-release
```
