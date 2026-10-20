# tompero-helm

A Helm chart for deploying [Chez Tomperô](https://github.com/jfms7s/tompero),
a self-hosted recipe manager and meal planner (recipe variants, ingredient
tips, linked recipes, Mealie import). The app is a single container: the
Rust server embeds the web app and keeps its data in SQLite under `/data`,
or in Postgres when given a `DATABASE_URL`.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A pull secret for `ghcr.io/jfms7s/tompero` while the image is private

## Installing the Chart

```bash
helm install my-release . \
  --set imagePullSecrets[0].name=ghcr-pull \
  --set server.persistence.volume.persistentVolumeClaim.claimName=tompero-data
```

No credentials are needed for the default SQLite setup. The first visit to
the app creates the household and its admin account.

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | Tomperô server image | `ghcr.io/jfms7s/tompero:v0.1.0` |
| `imagePullSecrets` | Pull secrets for the (private) image, e.g. `[{name: ghcr-pull}]` | `[]` |
| `server.secureCookies` | Mark the session cookie `Secure` (set `true` when served over HTTPS) | `false` |
| `server.logLevel` | Log filter (`LOG_LEVEL`, RUST_LOG syntax) | `info,sqlx=warn` |
| `server.databaseUrl` | Postgres URL, a standard Kubernetes EnvVarSource; empty uses SQLite in `/data` (see note below) | `value: ""` |
| `server.extraEnv` | Extra env vars for the server container: `{name, value}` or `{name, valueFrom}` (an EnvVarSource, e.g. `TOMPERO_SECRET_KEY` from a Secret) | `[]` |
| `server.persistence.volume` | Volume source (excl. `name`) for `/data` (SQLite database and images) | `{}` (emptyDir) |
| `server.persistence.claim` | `{storageClassName, size}`: when the class is set, render a PVC `<release>-tompero-server-data` (RWO, kept on uninstall/prune); point `server.persistence.volume` at it via `persistentVolumeClaim.claimName` | unset |
| `server.persistence.subPath` | Subdirectory of the volume to mount as `/data` (keeps ext4's `lost+found` out of it on block-backed PVCs) | `""` |
| `resources` / `securityContext` / `podSecurityContext` | Server container/pod settings | `{}` |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the server | disabled |

### Database

SQLite is the default and needs nothing configured. To use Postgres instead,
set `server.databaseUrl`, a standard Kubernetes `EnvVarSource`. Argo CD does
not support Helm's `lookup` function, so the chart never generates or stores
credentials itself: either set `server.databaseUrl.value` from a secrets file
kept out of version control, or point `server.databaseUrl.valueFrom` at a
Secret you manage (`valueFrom` wins when both are set):

```yaml
server:
  databaseUrl:
    valueFrom:
      secretKeyRef:
        name: tompero-secrets
        key: database-url
```

### Persistent storage

`/data` holds the SQLite database (unless Postgres is used) and every
uploaded or imported image, so it needs a real volume. The chart ships no
default backend since the right one is environment-specific;
`server.persistence.volume` takes the full body of a Kubernetes volume
source, e.g.:

```yaml
server:
  persistence:
    volume:
      nfs:
        server: 192.168.1.10
        path: /volumes/tompero/data
```

The container runs as uid 65532 (distroless `nonroot`), so the volume must
be writable by that user: set `podSecurityContext.fsGroup: 65532` for
volumes that honour `fsGroup` (PVCs), or chown the export for NFS.

Leaving `volume` unset falls back to `emptyDir` (non-persistent), which is
fine for a quick test, not for real recipes.

### Hardening

The image only writes to `/data`, so the usual hardening works unchanged:

```yaml
securityContext:
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: [ALL]
```

## Deployment

This chart creates a Deployment (one replica, `Recreate` strategy, since a
single volume backs the database) + Service (+ optional Ingress and PVC) for
the Tomperô server. Probes hit `GET /api/health` on port 8080.

## Uninstalling

```bash
helm uninstall my-release
```

A chart-created PVC is kept on uninstall; delete it by hand to remove the data.
