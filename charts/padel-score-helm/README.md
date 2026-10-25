# padel-score-helm

A Helm chart for deploying [padel-score](https://github.com/jfms7s/padel-score),
a padel match scorer with live spectator links. The app is a single container:
the Rust server embeds the web app and keeps its data in SQLite under `/data`.
The image is public, so no pull secret is needed.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installing the Chart

```bash
helm install my-release . \
  --set server.persistence.volume.persistentVolumeClaim.claimName=my-release-padel-score-server-data
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | padel-score server image | `ghcr.io/jfms7s/padel-score:v0.1.0` |
| `imagePullSecrets` | Pull secrets, only needed for a private mirror | `[]` |
| `server.logLevel` | Log filter (`LOG_LEVEL`, RUST_LOG syntax) | `info,sqlx=warn` |
| `server.extraEnv` | Extra env vars for the server container: `{name, value}` or `{name, valueFrom}` | `[]` |
| `server.persistence.volume` | Volume source (excl. `name`) for `/data` (the SQLite database) | `{}` (emptyDir) |
| `server.persistence.claim` | `{storageClassName, size}`: when the class is set, render a PVC `<release>-padel-score-server-data` (RWO, kept on uninstall/prune); point `server.persistence.volume` at it via `persistentVolumeClaim.claimName` | unset |
| `server.persistence.subPath` | Subdirectory of the volume to mount as `/data` | `""` |
| `resources` / `securityContext` / `podSecurityContext` | Server container/pod settings | `{}` |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the server | disabled |

### Persistent storage

`/data` holds the SQLite database, so it needs a real volume. The container
runs as uid 65532 (distroless `nonroot`), so the volume must be writable by
that user: set `podSecurityContext.fsGroup: 65532` for volumes that honour
`fsGroup` (PVCs), or chown the export for NFS. Leaving `volume` unset falls
back to `emptyDir` (non-persistent), fine for a quick test only.

### Live updates (SSE)

The app streams scores over Server-Sent Events. Traefik streams
`text/event-stream` by default, so the Ingress needs no middleware. Behind a
buffering proxy, disable response buffering for `/api/`.

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

A Deployment (one replica, `Recreate` strategy, since SQLite allows a single
writer) + Service (+ optional Ingress and PVC). Probes hit `GET /api/health`
on port 8080.

## Uninstalling

```bash
helm uninstall my-release
```

A chart-created PVC is kept on uninstall; delete it by hand to remove the data.
