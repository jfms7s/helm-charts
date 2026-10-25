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
  --set server.persistence.claim.size=1Gi \
  --set server.persistence.volume.persistentVolumeClaim.claimName=my-release-padel-score-server-data
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | padel-score server image | `ghcr.io/jfms7s/padel-score:v0.2.0` |
| `imagePullSecrets` | Pull secrets, only needed for a private mirror | `[]` |
| `server.logLevel` | Log filter (`LOG_LEVEL`, RUST_LOG syntax) | `info,sqlx=warn` |
| `server.secureCookies` | `SECURE_COOKIES`: Secure attribute on session cookies | `true` |
| `server.trustedProxies` | `TRUSTED_PROXIES`: CIDRs/IPs whose forwarded headers are trusted; omitted when empty | `""` |
| `server.publicOrigin` | `PUBLIC_ORIGIN`: public site origin, e.g. `https://padel.example.com`; omitted when empty | `""` |
| `server.setupToken` | `SETUP_TOKEN` as `{value, valueFrom}` (e.g. a secretKeyRef); `valueFrom` wins; omitted when both unset | unset |
| `server.extraEnv` | Extra env vars for the server container: `{name, value}` or `{name, valueFrom}` | `[]` |
| `server.persistence.ephemeral` | Opt in to a non-persistent emptyDir; without it, rendering fails unless `volume` is set | `false` |
| `server.persistence.volume` | Volume source (excl. `name`) for `/data` (the SQLite database) | `{}` (emptyDir) |
| `server.persistence.claim` | `{storageClassName, size}`: when `size` is set, render a PVC `<release>-padel-score-server-data` (RWO, kept on uninstall/prune; empty class = cluster default); point `server.persistence.volume` at it via `persistentVolumeClaim.claimName` | unset |
| `server.persistence.subPath` | Subdirectory of the volume to mount as `/data` | `""` |
| `resources` / `securityContext` / `podSecurityContext` | Server container/pod settings | hardened (uid/gid 65532, read-only root, drop ALL, seccomp RuntimeDefault, fsGroup 65532) |
| `ingress.enabled` / `ingress.className` / `ingress.hosts` / `ingress.tls` | Ingress for the server | disabled |

### Persistent storage

`/data` holds the SQLite database, so it needs a real volume. The container
runs as uid 65532 (distroless `nonroot`), so the volume must be writable by
that user: set `podSecurityContext.fsGroup: 65532` for volumes that honour
`fsGroup` (PVCs), or chown the export for NFS. Leaving `volume` unset fails the render, so data is never lost silently; set
`server.persistence.ephemeral=true` to opt in to a non-persistent `emptyDir`
(quick tests only).

### Live updates (SSE)

The app streams scores over Server-Sent Events. Traefik streams
`text/event-stream` by default, so the Ingress needs no middleware. Behind a
buffering proxy, disable response buffering for `/api/`.

### Hardening

Defaults are hardened: non-root uid/gid 65532, read-only root filesystem
(a `/tmp` emptyDir is mounted), no privilege escalation, all capabilities
dropped, `RuntimeDefault` seccomp, `fsGroup` 65532.

## Deployment

A Deployment (one replica, `Recreate` strategy, since SQLite allows a single
writer) + Service (+ optional Ingress and PVC). Startup, liveness and readiness probes hit `GET /api/health` on port 8080
(the startup probe allows up to 5 minutes).

## Uninstalling

```bash
helm uninstall my-release
```

A chart-created PVC is kept on uninstall; delete it by hand to remove the data.
