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

Set `postgres.password`, `redis.password`, `server.jwtSecret`,
`server.sessionSecret`, and `server.aiEncryptionKey` explicitly before
installing — see the note below.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | PatchMon server image | `ghcr.io/patchmon/patchmon-server:latest` |
| `replicas` | PatchMon server replica count | `1` |
| `server.corsOrigin` | Allowed frontend origin(s), comma-separated | `http://localhost:3000` |
| `server.jwtSecret` / `server.sessionSecret` / `server.aiEncryptionKey` | Server secrets (see note below) | `"CHANGE_ME"` |
| `server.existingSecret` | Use a pre-existing Secret for the three server secrets above instead (see note below) | `""` |
| `server.existingSecretJwtKey` / `server.existingSecretSessionKey` / `server.existingSecretAiEncryptionKey` | Keys within `server.existingSecret` | `"jwt-secret"` / `"session-secret"` / `"ai-encryption-key"` |
| `server.extraEnv` | Extra `{name, value}` env vars for the server container | `[]` |
| `postgres.image.*` | Postgres image | `postgres:17-alpine` |
| `postgres.db` / `postgres.user` | Postgres database/user | `patchmon_db` / `patchmon_user` |
| `postgres.password` | Postgres password (see note below) | `"CHANGE_ME"` |
| `postgres.existingSecret` / `postgres.existingSecretPasswordKey` | Use a pre-existing Secret for the password instead of `postgres.password` (see note below) | `""` / `"postgres-password"` |
| `postgres.resources` | Postgres container resources | `{}` |
| `postgres.persistence.volume` | Volume source (excl. `name`) for the Postgres data dir | `{}` (emptyDir) |
| `redis.image.*` | Redis image | `redis:7-alpine` |
| `redis.password` | Redis password (see note below) | `"CHANGE_ME"` |
| `redis.existingSecret` / `redis.existingSecretPasswordKey` | Use a pre-existing Secret for the password instead of `redis.password` (see note below) | `""` / `"redis-password"` |
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
`server.sessionSecret`, and `server.aiEncryptionKey` must all be set
explicitly by the caller, e.g. from a secrets file kept out of version
control. Generate each of the server secrets with:

```bash
openssl rand -hex 64
```

Alternatively, set the matching `<resource>.existingSecret` (`server.`,
`postgres.`, `redis.`) to the name of a Secret you manage yourself (e.g. one
synced by an external secrets manager) holding the values under the
corresponding `existingSecret*Key` value(s) above. When set, this chart
stops rendering its own Secret for that resource and every consumer
references the external one instead. Leave `existingSecret` unset to keep
the default plaintext-`values.yaml` behavior described above — the two are
mutually exclusive per resource, not layered, and each of the three
resources (server/postgres/redis) toggles independently.

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
for Redis, a Deployment + Service for guacd, a Secret holding the Postgres
password, a Secret holding the Redis password, and a Secret holding the
server's JWT/session/AI-encryption secrets.

## Uninstalling

```bash
helm uninstall my-release
```
