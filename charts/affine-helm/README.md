# affine-helm

A Helm chart for deploying [Affine](https://affine.pro/), a self-hosted
workspace/collaboration app, along with its Postgres (pgvector) database and
Redis cache.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installing the Chart

```bash
helm install my-release .
```

Set `postgres.password` explicitly before installing — see the note below.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | Affine server image | `ghcr.io/toeverything/affine:stable` |
| `replicas` | Affine server replica count | `1` |
| `persistence.config.volume` | Volume source (excl. `name`) for `/root/.affine/config` | `{}` (emptyDir) |
| `persistence.storage.volume` | Volume source (excl. `name`) for `/root/.affine/storage` | `{}` (emptyDir) |
| `postgres.image.*` | Postgres (pgvector) image | `pgvector/pgvector:pg16` |
| `postgres.db` / `postgres.user` | Postgres database/user | `affine` / `affine` |
| `postgres.password` | Postgres password (see note below) | `"CHANGE_ME"` |
| `postgres.resources` | Postgres container resources | `{}` |
| `postgres.persistence.volume` | Volume source (excl. `name`) for the Postgres data dir | `{}` (emptyDir) |
| `redis.image.*` | Redis image | `redis:latest` |
| `redis.resources` | Redis container resources | `{}` |
| `copilot.enabled` | Enable Affine's AI features | `false` |
| `copilot.openai.apiKey` / `copilot.openai.baseUrl` | Server-wide OpenAI-compatible provider credentials | `""` / `https://api.openai.com/v1` |
| `resources` / `securityContext` / `podSecurityContext` | Affine server container/pod settings | `{}` |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the Affine server | disabled |

### Postgres password

Argo CD does not support Helm's `lookup` function, so this chart can't safely
auto-generate a random password and persist it across syncs the way a plain
`helm install` could — it would silently rotate (and lock you out of your
data) on the next sync. `postgres.password` must be set explicitly by the
caller, e.g. from a secrets file kept out of version control.

### Persistent storage

None of the three workloads (Affine server, Postgres, Redis's `/data` isn't
persisted) ship a default storage backend, since the right one (NFS,
hostPath, a PVC, cloud block storage, ...) is environment-specific. Each
`*.volume` value takes the full body of a Kubernetes volume source
(everything except `name`), e.g.:

```yaml
persistence:
  config:
    volume:
      nfs:
        server: 192.168.1.10
        path: /volumes/affine/config
```

Leaving a `volume` unset falls back to `emptyDir` (non-persistent) — fine
for a quick test, not for real data.

### AI features (copilot)

As of server version 0.27, Affine no longer reads `OPENAI_API_KEY`/
`OPENAI_BASE_URL` env vars for AI configuration — that moved to a
`config.json` file read from `/root/.affine/config/config.json` (see
[the self-host configuration docs](https://docs.affine.pro/self-host-affine/install/configuration)).
This chart renders that file from `copilot.*` values into a Secret and mounts
it read-only over the persistent config volume, so setting `copilot.enabled`
and `copilot.openai.apiKey` is all that's needed to preconfigure a
server-wide OpenAI-compatible provider. Provider keys can also be set later,
per-workspace, from the Affine UI itself (Workspace Settings → Integrations
→ AI BYOK) without touching this chart at all.

## Deployment

This chart creates: a Deployment + Service (+ optional Ingress) for the
Affine server, a Deployment + Service for Postgres, a Deployment + Service
for Redis, a Secret holding the Postgres password, a Secret holding the
rendered `copilot` `config.json`, and a post-install/post-upgrade migration
Job.

## Uninstalling

```bash
helm uninstall my-release
```
