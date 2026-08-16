# patchmon-helm

A Helm chart for deploying [PatchMon](https://patchmon.net/), a self-hosted
Linux patch management platform, along with its Postgres database, Redis
cache, and guacd (in-browser RDP) sidecar. Modeled on upstream's
[docker-compose.yml](https://github.com/PatchMon/PatchMon/blob/main/docker/docker-compose.yml).

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installing the Chart

```bash
helm install my-release .
```

Set `postgres.password.value`, `redis.password.value`,
`server.jwtSecret.value`, `server.sessionSecret.value`, and
`server.aiEncryptionKey.value` (or the matching `.valueFrom`) explicitly
before installing — see the note below.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | PatchMon server image | `ghcr.io/patchmon/patchmon-server:latest` |
| `replicas` | PatchMon server replica count | `1` |
| `server.corsOrigin` | Allowed frontend origin(s), comma-separated | `http://localhost:3000` |
| `server.jwtSecret` / `server.sessionSecret` / `server.aiEncryptionKey` | Server secrets, each a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `server.extraEnv` | Extra `{name, value}` env vars for the server container | `[]` |
| `postgres.image.*` | Postgres image | `postgres:17-alpine` |
| `postgres.db` / `postgres.user` | Postgres database/user | `patchmon_db` / `patchmon_user` |
| `postgres.password` | Postgres password, a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `postgres.resources` | Postgres container resources | `{}` |
| `postgres.persistence.volume` | Volume source (excl. `name`) for the Postgres data dir | `{}` (emptyDir) |
| `redis.image.*` | Redis image | `redis:7-alpine` |
| `redis.password` | Redis password, a standard Kubernetes EnvVarSource (see note below) | `value: "CHANGE_ME"` |
| `redis.resources` | Redis container resources | `{}` |
| `redis.persistence.volume` | Volume source (excl. `name`) for the Redis data dir | `{}` (emptyDir) |
| `guacd.enabled` | Deploy the guacd sidecar (in-browser RDP to Windows hosts) | `true` |
| `guacd.image.*` | guacd image | `guacamole/guacd:latest` |
| `guacd.resources` | guacd container resources | `limits: {cpu: "1", memory: 512Mi}` |
| `resources` / `securityContext` / `podSecurityContext` | PatchMon server container/pod settings | `{}` |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the PatchMon server | disabled |

### Secrets

Argo CD does not support Helm's `lookup` function, so this chart can't
safely auto-generate random secrets and persist them across syncs the way a
plain `helm install` could — they would silently rotate (locking out
sessions and re-encrypting nothing, since the old key would be lost) on the
next sync. `postgres.password`, `redis.password`, `server.jwtSecret`,
`server.sessionSecret`, and `server.aiEncryptionKey` are each a standard
Kubernetes `EnvVarSource` (the same shape as a container's `env[].valueFrom`):
set `<field>.value` to a plain literal, e.g. from a secrets file kept out of
version control (generate each of the server secrets with
`openssl rand -hex 64`), or `<field>.valueFrom` (e.g. a `secretKeyRef`) to
source it from a Secret you manage yourself instead (an external secrets
manager, ...). `valueFrom` takes precedence whenever it's set, and each of
the five fields toggles independently:

```yaml
postgres:
  password:
    valueFrom:
      secretKeyRef:
        name: patchmon-secrets
        key: postgres-password
```

### Persistent storage

Neither Postgres nor Redis ship a default storage backend, since the right
one (NFS, hostPath, a PVC, cloud block storage, ...) is environment-specific.
Each `*.persistence.volume` value takes the full body of a Kubernetes volume
source (everything except `name`), e.g.:

```yaml
postgres:
  persistence:
    volume:
      nfs:
        server: 192.168.1.10
        path: /volumes/patchmon/postgres
```

Leaving a `volume` unset falls back to `emptyDir` (non-persistent) — fine
for a quick test, not for real data.

### guacd (in-browser RDP)

PatchMon's optional Windows RDP feature proxies through
[Apache Guacamole's guacd](https://guacamole.apache.org/), run read-only
with all Linux capabilities dropped and no privilege escalation, matching
upstream's docker-compose hardening. Set `guacd.enabled: false` to omit it
if the RDP feature isn't needed.

## Deployment

This chart creates: a Deployment + Service (+ optional Ingress) for the
PatchMon server, a Deployment + Service for Postgres, a Deployment + Service
for Redis, and a Deployment + Service for guacd.

## Uninstalling

```bash
helm uninstall my-release
```
