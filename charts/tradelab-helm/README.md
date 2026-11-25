# tradelab-helm

A Helm chart for deploying [tradelab](https://github.com/jfms7s/tradelab), a
platform to test investment agents on a simulated stock market with real minute
prices, then run a trusted one with fake money on live prices. One pod runs
three containers from one image (`ghcr.io/jfms7s/tradelab`), all sharing one
SQLite database under `/data`:

- `api`: `tradelab-app serve`, the dashboard and its API on port 8080;
- `worker`: `tradelab-app worker`, queued replay runs;
- `live`: `tradelab-app live`, the live driver (live prices, fake money).

An optional nightly CronJob copies the database with `tradelab-app backup`. The
image is private, so set a pull secret.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+
- A Secret with the Alpaca paper keys `APCA_API_KEY_ID` and
  `APCA_API_SECRET_KEY` (needed while `live.enabled`)

## Installing the Chart

```bash
helm install my-release . \
  --set imagePullSecrets[0].name=ghcr-pull \
  --set alpaca.existingSecret=tradelab-alpaca \
  --set persistence.claim.size=5Gi \
  --set persistence.volume.persistentVolumeClaim.claimName=my-release-tradelab-data
```

## Configuration

| Parameter | Description | Default |
|-----------|-------------|---------|
| `image.repository` / `image.tag` / `image.pullPolicy` | tradelab image, for every container and the backup | `ghcr.io/jfms7s/tradelab:v0.1.0` |
| `imagePullSecrets` | Pull secrets (the image is private) | `[]` |
| `host` | Ingress host; also in the api's `TRADELAB_ALLOWED_HOSTS` after the pod IP | `""` |
| `alpaca.existingSecret` | Secret with `APCA_API_KEY_ID` and `APCA_API_SECRET_KEY`, for worker and live only (never the api). Rendering fails while `live.enabled` and this is empty | `""` |
| `api.resources` | api container resources | `{}` |
| `worker.enabled` / `worker.requestsPerMinute` / `worker.resources` | The worker container and its Alpaca pace (`TRADELAB_ALPACA_REQUESTS_PER_MINUTE`) | `true` / `110` / `{}` |
| `live.enabled` / `live.requestsPerMinute` / `live.resources` | The live container and its Alpaca pace | `true` / `60` / `{}` |
| `persistence.volume` | Volume source (excl. `name`) for `/data`; rendering fails while empty | `{}` |
| `persistence.claim` | `{storageClassName, size}`: when `size` is set, render a PVC `<release>-tradelab-data` (RWO, kept on uninstall/prune; empty class = cluster default); point `persistence.volume` at it | unset |
| `persistence.subPath` | Subdirectory of the volume to mount as `/data` | `""` |
| `seLinuxLevel` | `seLinuxOptions.level` for the app pod and the backup Job | `""` |
| `backup.enabled` / `backup.schedule` / `backup.keep` | Nightly backup CronJob, its schedule and the copies kept | `false` / `30 2 * * *` / `14` |
| `backup.volume` | Volume source (excl. `name`) for `/backup`; required when enabled | `{}` |
| `backup.claim` | `{storageClassName, size}`: when enabled and `size` is set, render a PVC `<release>-tradelab-backup` (kept on uninstall/prune) | unset |
| `backup.resources` | Backup container resources | `{}` |
| `metrics.serviceMonitor.enabled` / `.interval` / `.labels` | ServiceMonitor for `GET /metrics` on the Service's `http` port | `false` / `30s` / `{}` |
| `nodeSelector` / `affinity` / `tolerations` | App pod placement (the backup Job takes `nodeSelector` and `tolerations`, and follows the app pod by affinity) | unset |
| `securityContext` / `podSecurityContext` | Container/pod settings, for every container and the backup | hardened (uid/gid 65532, read-only root, drop ALL, seccomp RuntimeDefault, fsGroup 65532) |
| `ingress.enabled` / `ingress.className` / `ingress.annotations` | Ingress for `host` on `/`; rendering fails without `host` | disabled |

### Persistent storage

`/data` holds the SQLite database (WAL mode) and the price store, shared by the
three containers of the one pod. WAL needs a local block volume: use a
ReadWriteOnce iSCSI claim, never NFS or a ReadWriteMany volume. The containers
run as uid 65532, so the volume must be writable by it (`fsGroup: 65532` does
that for claims). Leaving `persistence.volume` unset fails the render, so data
is never lost silently.

### The Host check

The app answers only to loopback names and `TRADELAB_ALLOWED_HOSTS`. The chart
sets it to `$(POD_IP),<host>`: Kubernetes expands the pod's own IP, which the
kubelet's probes and Prometheus send as Host, so both pass without any
exemption in the app.

### Probes

The api's startup and readiness probes hit `GET /api/health` (the startup
probe allows up to 5 minutes). `/api/health` answers 500 when the database
cannot be read, so the liveness probe asks for `GET /` (the dashboard's page,
which reads no database) instead: a passing database error takes the pod out of
the Service, it does not restart it. The worker and live containers have no
probes.

### Alpaca keys

Only `worker` and `live` get the keys, from `alpaca.existingSecret`. The live
driver exits 9 without them, so the chart refuses to render with `live.enabled`
and no Secret. The worker alone runs without keys on stored prices. The two
share Alpaca's limit of 200 requests a minute: keep `worker.requestsPerMinute`
and `live.requestsPerMinute` below it together.

### Backup

With `backup.enabled`, a CronJob `<release>-tradelab-backup` runs
`tradelab-app backup --to /backup --work /work --keep <keep>`: SQLite's online
backup (safe while the app writes) into `/work`, a local `emptyDir`, then kept
on `/backup` (`backup.volume`; NFS is fine there) with the newest `keep`
copies. `concurrencyPolicy: Forbid`, `activeDeadlineSeconds: 900` (a SIGTERM is
only handled once SQLite's copy call returns, so the deadline is the backstop),
`backoffLimit: 2`, finished Jobs deleted after a day. `/data` is mounted
read-write, since SQLite's WAL needs its `-shm` file even to read. The data
claim is RWO, so the Job has a required pod affinity to the app pod's node;
set `seLinuxLevel` on SELinux nodes so the Job shares the app pod's level and
never relabels the volume.

### Hardening

Defaults are hardened: non-root uid/gid 65532, read-only root filesystem (a
`/tmp` emptyDir is mounted), no privilege escalation, all capabilities dropped,
`RuntimeDefault` seccomp, `fsGroup` 65532, no service account token.

## Deployment

A Deployment (one replica, `Recreate`, `terminationGracePeriodSeconds: 60`:
SQLite has one writer pod) + Service (+ optional Ingress, PVCs, backup CronJob
and ServiceMonitor).

## Resource names

Part of the chart's interface (unit tests pin them). With release `tradelab` in namespace `tradelab`:

| Object | Name | Example |
|---|---|---|
| Service (port `http` 8080) | `<release>-tradelab` | `tradelab-tradelab.tradelab.svc` |
| Deployment / Ingress / ServiceMonitor | `<release>-tradelab` | `tradelab-tradelab` |
| Data PVC (when `persistence.claim.size` is set) | `<release>-tradelab-data` | `tradelab-tradelab-data` |
| Backup PVC and CronJob | `<release>-tradelab-backup` | `tradelab-tradelab-backup` |

A chart-made claim is not mounted automatically: point `persistence.volume` (or
`backup.volume`) at its `persistentVolumeClaim.claimName`.

## Uninstalling

```bash
helm uninstall my-release
```

Chart-created PVCs are kept on uninstall; delete them by hand to remove the data.
