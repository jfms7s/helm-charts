# First Dime Helm Chart

A Kubernetes Helm chart for deploying [First Dime](https://github.com/jfms7s/firstdime) (Number One Dime), a personal finance application.

Formerly `budget-manager-helm` (≤ 0.6.0).

## Overview

This chart deploys a complete First Dime stack on Kubernetes, including:

- **API Server**: Node.js Express API on port 3000 (Deployment + Service + Ingress)
- **Web Frontend**: Nginx static file server on port 8080 (Deployment + Service + Ingress)
- **Worker**: Async task processor, scheduler, and event bus relay (Deployment)
- **Database (sqld)**: LibSQL server (Deployment + Service, enabled by default, strategy: Recreate)
- **NATS JetStream**: In-cluster message bus for webhooks and events (Deployment + Service)
- **Frankfurter** (optional): exchange-rate API for the worker's hourly rate feed (Deployment + Service + PVC, disabled by default, strategy: Recreate)
- **bank-sync** (optional): [Enable Banking](https://enablebanking.com) client that pushes booked bank transactions into the api through `POST /imports` (Deployment + Service + Ingress + PVC, disabled by default, strategy: Recreate). See [Bank sync](#bank-sync)

The application stores user attachments in a shared volume. By default, the chart deploys an in-cluster LibSQL database; you can optionally disable it and point to an external Turso database instead.

## Prerequisites

1. Kubernetes 1.24+
2. Helm 3.0+
3. For production: RWX storage (NFS) for attachments; block storage (iSCSI, RWO) for sqld, NATS, Frankfurter and bank-sync (if enabled)
4. Optional: external Turso database URL and token (if sqld.enabled: false)

## Installation

### 1. Create a namespace

```bash
kubectl create namespace firstdime
```

### 2. Create required secrets

The chart expects credentials to be provided via Kubernetes Secrets. You can either:

**Option A: Use External Secrets Operator (recommended for Argo CD)**

The chart supports ExternalSecrets integration. Configure your External Secrets Operator with OpenBao or another secret backend, then reference the secrets in your values:

```yaml
database:
  authToken:
    valueFrom:
      secretKeyRef:
        name: firstdime-secrets
        key: db-auth-token
sessionCookieSecret:
  valueFrom:
    secretKeyRef:
      name: firstdime-secrets
      key: session-cookie-secret
appEncryptionKey:
  valueFrom:
    secretKeyRef:
      name: firstdime-secrets
      key: app-encryption-key
```

**Option B: Create secrets manually**

```bash
kubectl create secret generic firstdime-secrets \
  --from-literal=db-auth-token=<your-token> \
  --from-literal=session-cookie-secret=<your-secret> \
  --from-literal=app-encryption-key=<your-key> \
  -n firstdime
```

### 3. Configure values

Create a `values-firstdime.yaml` file with your environment-specific settings:

```yaml
database:
  url: "http://firstdime-sqld:8080"  # or your Turso URL
  authToken:
    valueFrom:
      secretKeyRef:
        name: firstdime-secrets
        key: db-auth-token

sessionCookieSecret:
  valueFrom:
    secretKeyRef:
      name: firstdime-secrets
      key: session-cookie-secret

appEncryptionKey:
  valueFrom:
    secretKeyRef:
      name: firstdime-secrets
      key: app-encryption-key

ingress:
  web:
    host: budget.example.com
  api:
    host: budget-api.example.com

attachments:
  volume:
    nfs:
      server: 192.168.1.10
      path: /volume1/k8s/volumes/firstdime/attachments

nats:
  persistence:
    volume:
      nfs:
        server: 192.168.1.10
        path: /volume1/k8s/volumes/firstdime/nats
```

### 4. Install the chart

```bash
helm install firstdime ./firstdime-helm \
  -n firstdime \
  -f values-firstdime.yaml
```

## Resource names

Every resource is named `<fullname>-<component>`, where `<fullname>` is the release name when it
already contains `firstdime`, else `<release>-firstdime` (truncated to 50 characters). So release
`firstdime` gives `firstdime-api`, `firstdime-web`, `firstdime-worker`, `firstdime-sqld`,
`firstdime-nats` and `firstdime-bank-sync`, and default claims `firstdime-{sqld,nats,frankfurter,bank-sync}-data`.

0.7.0 changed this scheme (0.6.0 named them `<release>-<old chart name>-<component>`), so every
resource and default PVC name changes on the move to 0.7.0: it is a data migration, not an in-place
`helm upgrade`.

## Configuration

### Required Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `database.url` | libSQL database URL | `CHANGE_ME` |
| `database.authToken.value` or `valueFrom` | Database authentication token | `CHANGE_ME` |
| `sessionCookieSecret.value` or `valueFrom` | Session cookie encryption secret | `CHANGE_ME` |
| `appEncryptionKey.value` or `valueFrom` | Encryption key for webhook secrets and 2FA | `CHANGE_ME` |

### Optional Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `registrationEnabled` | Allow new user registration via sign-up form | `true` |
| `trustProxy` | Proxies whose X-Forwarded-For the api believes (`TRUST_PROXY`): comma-separated addresses or CIDRs, e.g. `10.42.0.0/16` on k3s. Empty trusts nobody; never `true` | `""` |
| `tz` | Time zone (IANA format) | `UTC` |
| `ingress.api.host` | API server hostname | `budget-api.example.com` |
| `ingress.web.host` | Web frontend hostname | `budget.example.com` |
| `smtp.url.value` or `valueFrom` | SMTP server URL (enables email notifications) | `` |
| `smtp.from.value` or `valueFrom` | From email address | `` |
| `imagePullSecrets` | Image pull secrets for private registries | `[]` |
| `attachments.volume` | Volume source for attachments storage | `emptyDir` |
| `nats.persistence.volume` | Volume source for NATS data | `emptyDir` |
| `sqld.persistence.claim` / `nats.persistence.claim` / `frankfurter.persistence.claim` / `bankSync.persistence.claim` | `{name, storageClassName, size}`: when the class is set, render a PVC named `name`, default `<fullname>-<sqld\|nats\|frankfurter\|bank-sync>-data` (RWO, kept on uninstall/prune); point `persistence.volume` at it via `persistentVolumeClaim.claimName`. A claim's class can't change in place: to move storage, set a new `name` (the old claim is kept) | unset |
| `sqld.persistence.subPath` / `nats.persistence.subPath` / `frankfurter.persistence.subPath` / `bankSync.persistence.subPath` | Subdirectory of the volume to mount as the data dir (use on block-backed PVCs to keep ext4's `lost+found` out of it) | `""` |
| `sqld.checkpointIntervalSeconds` | WAL checkpoint interval (`--checkpoint-interval-s`). Set, sqld turns off per-commit auto-checkpoints and runs one `TRUNCATE` checkpoint per interval (see [sqld's write lock](#sqlds-write-lock)) | `""` (sqld default) |
| `sqld.writeProbe.enabled` | Liveness probe that writes (`BEGIN IMMEDIATE; ROLLBACK` over `/v2/pipeline`, bash `/dev/tcp`) instead of a TCP check | `false` |
| `sqld.writeProbe.{timeoutSeconds,periodSeconds,failureThreshold,initialDelaySeconds}` | Write probe timing: the script waits `timeoutSeconds` for sqld's answer (kubelet's timeout is one more) | `10`, `30`, `3`, `30` |
| `sqld.extraArgs` / `sqld.extraEnv` | Extra sqld command-line arguments / environment variables | `[]` |
| `frankfurter.enabled` | Deploy the self-hosted [Frankfurter](https://github.com/lineofflight/frankfurter) exchange-rate API (Deployment + Service) and give the worker `FRANKFURTER_URL`, which turns on its hourly `exchange-rate-fetch` job. Needs outbound internet to the central banks it downloads from | `false` |
| `frankfurter.image.{repository,tag,pullPolicy}` | Frankfurter image (Docker Hub only; mirror it and set `imagePullSecrets` if the cluster can't reach Docker Hub) | `docker.io/lineofflight/frankfurter`, `v2.6.1`, `IfNotPresent` |
| `frankfurter.workerProcesses` | Puma web worker processes (`WORKER_PROCESSES`). `0` = Puma single mode, one process; the image default is 4 | `0` |
| `frankfurter.persistence.{volume,claim,subPath}` | Volume source (REQUIRED when enabled), optional chart-created PVC, and subPath for Frankfurter's SQLite database, mounted at `/app/data`. Use block storage (iSCSI), never NFS. Size the claim at 5Gi or more: a partial backfill (9 of 104 providers) was already 170 MB | unset |
| `frankfurter.extraEnv` | Extra environment variables for Frankfurter | `[]` |
| `frankfurter.nodeSelector` / `frankfurter.tolerations` / `frankfurter.affinity` | Pod placement for Frankfurter, e.g. a dedicated node pool. With node-local storage (local-path) the pod stays on the node where its claim was first bound | `{}` / `[]` / `{}` |
| `bankSync.enabled` | Deploy bank-sync (Deployment + Service + Ingress). See [Bank sync](#bank-sync) | `false` |
| `bankSync.image.{repository,tag,pullPolicy}` | bank-sync image (private ghcr, like the other First Dime images) | `ghcr.io/jfms7s/firstdime-bank-sync`, `v0.18.0`, `IfNotPresent` |
| `bankSync.host` | Admin page host (REQUIRED when enabled; bare hostname). `BANK_SYNC_PUBLIC_URL` is `https://<host>`, and the Enable Banking app's redirect URL must be exactly `https://<host>/callback`. Routed with `ingress.className` and `ingress.annotations` | `""` |
| `bankSync.tls` | TLS for the bank-sync Ingress; empty uses `ingress.tls` (whose hosts must then include `bankSync.host`) or the cluster's default certificate | `[]` |
| `bankSync.{ebAppId,fdToken,adminPasswordHash,sessionSecret}` | `value` or `valueFrom` (REQUIRED when enabled): `BANK_SYNC_EB_APP_ID`, `BANK_SYNC_FD_TOKEN` (PAT with exactly `imports:write imports:read accounts:read`), `BANK_SYNC_ADMIN_PASSWORD_HASH` (argon2id, from bank-sync's `hash-password`), `BANK_SYNC_SESSION_SECRET` (32+ characters) | unset |
| `bankSync.privateKeySecret.{name,key}` | Secret and key holding the Enable Banking application's PEM private key (name REQUIRED when enabled). Only that key is mounted, read-only, mode 0400, at `/run/secrets/eb/private.key` | `""`, `eb-private-key` |
| `bankSync.trustProxy` | Proxies whose X-Forwarded-For bank-sync believes (`BANK_SYNC_TRUST_PROXY`), so its login limiter sees client addresses: comma-separated addresses or CIDRs, e.g. `10.42.0.0/16` on k3s. Empty trusts nobody; `true` and hop counts fail the render | `""` |
| `bankSync.country` / `bankSync.logLevel` | `BANK_SYNC_EB_COUNTRY`, `LOG_LEVEL` | `PT`, `info` |
| `bankSync.persistence.{volume,claim,subPath}` | Volume source (REQUIRED when enabled), optional chart-created PVC, and subPath for bank-sync's SQLite file, mounted at `/app/.data`. Use block storage (iSCSI), never NFS | unset |
| `bankSync.extraEnv` / `bankSync.nodeSelector` / `bankSync.tolerations` / `bankSync.affinity` | Extra environment variables and pod placement for bank-sync | `[]` / `{}` / `[]` / `{}` |

### Resource Tuning

Memory requests and limits are set for a Raspberry Pi environment:

```yaml
api:
  resources:
    requests:
      memory: 160Mi
    limits:
      memory: 384Mi

worker:
  resources:
    requests:
      memory: 160Mi
    limits:
      memory: 384Mi

web:
  resources:
    requests:
      memory: 16Mi
    limits:
      memory: 64Mi

nats:
  resources:
    requests:
      memory: 32Mi
    limits:
      memory: 128Mi

# Only when frankfurter.enabled: measured 2026-10-06 (v2.6.1) at ~470-500 MB
# container usage during its initial backfill.
frankfurter:
  resources:
    requests:
      memory: 384Mi
    limits:
      memory: 768Mi

# Only when bankSync.enabled.
bankSync:
  resources:
    requests:
      memory: 96Mi
    limits:
      memory: 256Mi
```

Adjust these based on your workload and cluster capacity. **Note: CPU limits are not set** to prevent throttling issues on resource-constrained nodes.

## Storage Considerations

### Attachments Volume

The attachments volume is mounted at `/data/attachments` in both the API and worker pods. For production deployments:

- **Use shared storage (NFS/RWX)**: Allows pods to be rescheduled while maintaining access to user files
- **Local storage**: Use with `local-path` provisioner pinned to a single node if shared storage is unavailable

### NATS Data Volume

NATS JetStream data is stored at `/data` in the NATS pod. Configuration:

- **Default (emptyDir)**: Data is lost if the pod restarts
- **Production (NFS/RWX)**: Recommended for persistence across pod restarts

### Block storage (RWO PVCs) for sqld, NATS, Frankfurter and bank-sync

sqld, NATS, Frankfurter and bank-sync (when enabled) each run as a single `Recreate` Deployment, so all can sit on a ReadWriteOnce
block volume (e.g. a Synology iSCSI LUN) instead of NFS: set `<component>.persistence.claim` so
the chart creates the PVC, point `<component>.persistence.volume` at it, and set
`<component>.persistence.subPath` (e.g. `data`). Attachments can't move to RWO storage: both the
API and the worker mount them.

```yaml
sqld:
  persistence:
    claim: {storageClassName: synology-iscsi, size: 2Gi}
    subPath: data
    volume:
      persistentVolumeClaim:
        claimName: firstdime-sqld-data

# Frankfurter keeps a SQLite database (/app/data), so it needs block storage too.
frankfurter:
  enabled: true
  persistence:
    claim: {storageClassName: synology-iscsi, size: 5Gi}
    subPath: data
    volume:
      persistentVolumeClaim:
        claimName: firstdime-frankfurter-data

# bank-sync keeps a SQLite database (/app/.data), so it needs block storage too.
bankSync:
  persistence:
    claim: {storageClassName: synology-iscsi, size: 1Gi}
    subPath: data
    volume:
      persistentVolumeClaim:
        claimName: firstdime-bank-sync-data
```

## Bank sync

[bank-sync](https://github.com/jfms7s/firstdime/tree/main/apps/bank-sync) links bank accounts through
Enable Banking and, at the daily times of bank-sync's `BANK_SYNC_RUN_AT` (default `12:00,18:00,23:00`; set it through `bankSync.extraEnv`), pushes their booked transactions into this release's api
(`BANK_SYNC_FD_URL` is `http://<fullname>-api:80`, in-cluster). Its README covers registering the
Enable Banking application, the PAT and hashing the admin password. One instance per tenant.

```yaml
bankSync:
  enabled: true
  host: bank-sync.example.com          # redirect URL: https://bank-sync.example.com/callback
  trustProxy: "10.42.0.0/16"           # the ingress's pod network
  image:
    tag: "vX.Y.Z"                       # a First Dime release that ships bank-sync
  ebAppId:
    valueFrom: {secretKeyRef: {name: firstdime-bank-sync-secrets, key: eb-app-id}}
  fdToken:
    valueFrom: {secretKeyRef: {name: firstdime-bank-sync-secrets, key: bm-token}}
  adminPasswordHash:
    valueFrom: {secretKeyRef: {name: firstdime-bank-sync-secrets, key: admin-password-hash}}
  sessionSecret:
    valueFrom: {secretKeyRef: {name: firstdime-bank-sync-secrets, key: session-secret}}
  privateKeySecret:
    name: firstdime-bank-sync-secrets
    key: eb-private-key
  persistence:
    claim: {storageClassName: synology-iscsi, size: 1Gi}
    subPath: data
    volume:
      persistentVolumeClaim:
        claimName: firstdime-bank-sync-data
```

```bash
kubectl create secret generic firstdime-bank-sync-secrets -n firstdime \
  --from-literal=eb-app-id=<application id> \
  --from-literal=bm-token=<PAT> \
  --from-literal=admin-password-hash='<argon2id hash>' \
  --from-literal=session-secret=$(openssl rand -hex 32) \
  --from-file=eb-private-key=<path to the application's private key>
```

- **Exactly one replica, `Recreate`** (hardcoded): bank-sync keeps SQLite and in-memory admin sessions, and its
  startup clears any run lease a previous pod left. `terminationGracePeriodSeconds` is 30: on SIGTERM it waits up
  to 25 s for an in-flight run.
- **Only the admin page is routed.** The Service exposes port 80 (the admin page) and 9464 (`/metrics`, for
  in-cluster Prometheus); the Ingress routes `/` on `bankSync.host` to port 80 only. Never route 9464.
- **POSTs only work through the public URL** (bank-sync refuses a foreign `Origin`), so log in at
  `https://<host>`, not through a port-forward.
- Missing values fail the render: the host, the volume (or an `emptyDir` one), the private key Secret, any of the four credentials, a
  literal session secret under 32 characters, or a `trustProxy` entry that isn't an IP address or CIDR range (`true`, a hop count).
- **0.8.0 renamed `bankSync.bmToken` to `bankSync.fdToken`** (same `value`/`valueFrom` shape). A leftover `bmToken`
  fails the render, whether or not bank-sync is enabled. 0.8.0 set both `BANK_SYNC_FD_URL`/`BANK_SYNC_FD_TOKEN`
  and the old `BANK_SYNC_BM_URL`/`BANK_SYNC_BM_TOKEN`.
- **0.9.1 drops `bankSync.intervalHours`** and `BANK_SYNC_INTERVAL_HOURS` (bank-sync ignores it since `BANK_SYNC_RUN_AT`
  replaced it; a leftover value is ignored), and the image tags default to v0.18.0.
- **0.9.0 sets only `BANK_SYNC_FD_*`**, so it needs bank-sync **v0.18.0 or later** (earlier images read only the BM
  names and fail to start).

### sqld's write lock

libsql-server 0.24.33 serialises writers through its own write-lock queue, and a checkpoint or a
write that stalls for longer than its 5 s transaction timeout can leave that lock stuck for good
([tursodatabase/libsql#2286](https://github.com/tursodatabase/libsql/issues/2286)). When that
happens, reads keep working, every write hangs, sqld busy-spins its CPUs, and only a restart clears
it. Two settings limit the damage:

```yaml
sqld:
  # One checkpoint per minute instead of one per commit once the WAL is past 1000 pages.
  checkpointIntervalSeconds: 60
  # Restart sqld when a write has not gone through for ~3 probes (about 90 s).
  writeProbe:
    enabled: true
```

### Database and Backup Strategy

**Important**: The sqld database file and attachments volume must be backed up together to ensure consistency.

1. **Sqld**: Stored on NFS at `/volume1/k8s/volumes/firstdime/sqld` (managed by the `common` chart's libsql deployment)
2. **Attachments**: Stored on NFS at `/volume1/k8s/volumes/firstdime/attachments`
3. **NATS data**: Stored on NFS at `/volume1/k8s/volumes/firstdime/nats`

Backup all three directories as a single unit, and perform backups regularly using your NFS storage's snapshot or backup solution.

Frankfurter's data (when enabled) needs no backup: it re-downloads everything from the central banks.

## Usage

### Initial Setup

1. Access the web UI at `https://budget.example.com`
2. Create your account (if registration is enabled)
3. Begin recording transactions

### Disabling Sign-Up

Once you have created your account, disable public registration:

```yaml
registrationEnabled: false
```

Apply the change:

```bash
helm upgrade firstdime ./firstdime-helm \
  -n firstdime \
  -f values-firstdime.yaml
```

### Email Notifications

To enable email notifications (e.g., for scheduled reports):

```yaml
smtp:
  url:
    valueFrom:
      secretKeyRef:
        name: firstdime-secrets
        key: smtp-url
  from:
    valueFrom:
      secretKeyRef:
        name: firstdime-secrets
        key: smtp-from
```

Then create or update the secret:

```bash
kubectl create secret generic firstdime-secrets \
  --from-literal=smtp-url='smtp://user:password@smtp.example.com:587' \
  --from-literal=smtp-from='your-email@example.com' \
  -n firstdime --dry-run=client -o yaml | kubectl apply -f -
```

## Troubleshooting

### API pod fails to start: "CHANGE_ME" in logs

A required credential is still set to its placeholder value. Set the actual value in your Secret or values file.

### Web frontend shows "API origin not configured"

The `API_ORIGIN` environment variable is not set. Check that `ingress.api.host` is configured or explicitly set `apiOrigin`.

### Attachments not persisting across pod restarts

The attachments volume is likely an emptyDir. For production, configure a persistent volume (NFS recommended):

```yaml
attachments:
  volume:
    nfs:
      server: <nfs-server>
      path: <nfs-path>
```

### NATS pod logs show "permission denied" errors on NFS

Ensure the NFS volume has proper permissions for the workload to write to it. Containers run as numeric UIDs:
- **api/worker**: UID 1000 (the `node` user in the image)
- **nats**: UID 1000
- **web**: UID 101 (nginx-unprivileged)

**Important**: On NFS, Kubernetes `fsGroup` is not applied (NFS ignores it). Ensure NFS directories are **writable by UID 1000**. For example, on the Synology:
```bash
chmod 1770 /volume1/k8s/volumes/firstdime/nats
chmod 1770 /volume1/k8s/volumes/firstdime/attachments
chown 1000:1000 /volume1/k8s/volumes/firstdime/nats
chown 1000:1000 /volume1/k8s/volumes/firstdime/attachments
```

## Security

- **Non-root containers**: All containers run as non-root users
- **Read-only root filesystem**: Root filesystems are read-only; `emptyDir` volumes are provided for temporary files
- **Pod security**: `automountServiceAccountToken: false`, `securityContext.runAsNonRoot: true`, `capabilities.drop: [ALL]`
- **Credentials**: All sensitive data must be provided via Kubernetes Secrets with `secretKeyRef`

## Scaling

- **API**: Can be scaled by increasing `api.replicas`
- **Web**: Can be scaled by increasing `web.replicas`
- **Worker**: **Hardcoded to 1 replica** (runs the event bus relay and scheduler; multiple replicas would duplicate messages)
- **NATS**: **Hardcoded to 1 replica** (single broker model; HA would require additional configuration not included in this chart)
- **Frankfurter** / **bank-sync**: **Hardcoded to 1 replica** (one process per SQLite file)

## License

See [First Dime](https://github.com/jfms7s/firstdime) for license information.

## Support

For issues, feature requests, or questions:
- [First Dime GitHub](https://github.com/jfms7s/firstdime)
- [Helm Charts GitHub](https://github.com/jfms7s/helm-charts)
