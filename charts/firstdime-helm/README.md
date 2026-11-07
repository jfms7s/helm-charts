# First Dime Helm Chart

A Kubernetes Helm chart for deploying [First Dime](https://github.com/jfms7s/firstdime) (Number One Dime), a personal finance application.

Formerly `budget-manager-helm` (≤ 0.6.0).

## Overview

This chart deploys a complete First Dime stack on Kubernetes, including:

- **API Server**: Node.js Express API on port 3000 (Deployment + Service + Ingress)
- **Web Frontend**: Nginx static file server on port 8080 (Deployment + Service + Ingress)
- **Worker**: Async task processor, scheduler, and event bus relay (Deployment)
- **Database (Postgres 18)**: StatefulSet + Service on a block-storage (iSCSI) volume, used by the api and the worker. See [Postgres](#postgres)
- **Backups**: nightly `pg_dump` CronJob to an NFS export. See [Backups](#backups)
- **Database (sqld, legacy)** (optional): the old LibSQL server (Deployment + Service, off by default, strategy: Recreate), kept only for the move to Postgres. See [sqld](#sqld-legacy)
- **Copy Job** (optional): one-shot Job that copies sqld into Postgres and verifies it. See [Copy Job](#copy-job)
- **NATS JetStream**: In-cluster message bus for webhooks and events (Deployment + Service)
- **Frankfurter** (optional): exchange-rate API for the worker's hourly rate feed (Deployment + Service + PVC, disabled by default, strategy: Recreate)
- **bank-sync** (optional): [Enable Banking](https://enablebanking.com) client that pushes booked bank transactions into the api through `POST /imports` (Deployment + Service + Ingress + PVC, disabled by default, strategy: Recreate). See [Bank sync](#bank-sync)

The application stores user attachments in a shared volume. The api and worker run on Postgres; `postgres.enabled: false` points them at a Postgres outside the chart (they still read `DATABASE_URL` from `postgres.existingSecret`).

## Prerequisites

1. Kubernetes 1.27+ (CronJob `timeZone`, StatefulSet `persistentVolumeClaimRetentionPolicy`)
2. Helm 3.0+
3. For production: RWX storage (NFS) for attachments; block storage (iSCSI, RWO) for Postgres, NATS, Frankfurter and bank-sync (if enabled); an NFS export for the nightly Postgres dumps

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
postgres:
  existingSecret: firstdime-postgres   # keys POSTGRES_PASSWORD and DATABASE_URL
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
kubectl create secret generic firstdime-postgres \
  --from-literal=POSTGRES_PASSWORD=<password> \
  --from-literal=DATABASE_URL='postgres://firstdime:<url-encoded password>@firstdime-postgres:5432/firstdime' \
  -n firstdime
kubectl create secret generic firstdime-secrets \
  --from-literal=session-cookie-secret=<your-secret> \
  --from-literal=app-encryption-key=<your-key> \
  -n firstdime
```

### 3. Configure values

Create a `values-firstdime.yaml` file with your environment-specific settings:

```yaml
postgres:
  existingSecret: firstdime-postgres
  storageClass: synology-iscsi
  size: 2Gi

backup:
  nfs:
    server: 192.168.1.10
    path: /volume1/k8s/volumes/firstdime/postgres-backups

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
`firstdime` gives `firstdime-api`, `firstdime-web`, `firstdime-worker`, `firstdime-postgres`, `firstdime-postgres-backup`, `firstdime-copy`, `firstdime-sqld`,
`firstdime-nats` and `firstdime-bank-sync`, default claims `firstdime-{sqld,nats,frankfurter,bank-sync}-data`, and the Postgres claim `data-firstdime-postgres-0`.

0.7.0 changed this scheme (0.6.0 named them `<release>-<old chart name>-<component>`), so every
resource and default PVC name changes on the move to 0.7.0: it is a data migration, not an in-place
`helm upgrade`.

## Configuration

### Required Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgres.existingSecret` | Secret with keys `POSTGRES_PASSWORD` (initdb only) and `DATABASE_URL` (read by the api, worker, backup and copy Job). Required, also with `postgres.enabled: false` | `""` |
| `backup.nfs.{server,path}` | NFS export for the nightly dumps. Required while `backup.enabled` and `postgres.enabled` (else set `backup.enabled: false`) | `""` |
| `sessionCookieSecret.value` or `valueFrom` | Session cookie encryption secret | `CHANGE_ME` |
| `appEncryptionKey.value` or `valueFrom` | Encryption key for webhook secrets and 2FA | `CHANGE_ME` |

### Optional Values

| Parameter | Description | Default |
|-----------|-------------|---------|
| `postgres.enabled` | Deploy the Postgres StatefulSet + Service. `false` = use a Postgres outside the chart | `true` |
| `postgres.image.{repository,tag,pullPolicy}` | Postgres image (callers pin a digest) | `docker.io/library/postgres`, `18.6-bookworm`, `IfNotPresent` |
| `postgres.user` / `postgres.database` | `POSTGRES_USER` (the superuser, owns the database) / `POSTGRES_DB` | `firstdime` / `firstdime` |
| `postgres.storageClass` / `postgres.size` | Storage class (block storage, never NFS) and size of the data claim. Both required; the claim template is immutable once created | `synology-iscsi` / `2Gi` |
| `postgres.initdbArgs` | initdb flags, first start only | `--locale=C --encoding=UTF8` |
| `postgres.config` | Server settings, each `-c key=value`, values quoted strings (a bare number fails the render). Merges with the defaults; a `null` drops a key | `max_connections: "30"`, `shared_buffers: "128MB"` |
| `postgres.resources` | Requests/limits (sized for a 4 GB Pi) | `256Mi` / `512Mi` memory |
| `postgres.nodeSelector` / `postgres.tolerations` / `postgres.affinity` | Pod placement | `{}` / `[]` / `{}` |
| `backup.enabled` | Render the nightly `pg_dump` CronJob (needs `postgres.enabled`) | `true` |
| `backup.schedule` | Cron expression, always UTC | `30 2 * * *` |
| `backup.retainCount` | Dumps kept on the NAS (whole number, 1 or more) | `14` |
| `backup.runAsUser` / `backup.runAsGroup` | uid/gid of the backup pod; must own the NFS directory | `999` / `999` |
| `backup.resources` | Requests/limits of the backup container | `64Mi` / `256Mi` memory |
| `copyJob.enabled` | Render the one-shot copy Job. See [Copy Job](#copy-job) | `false` |
| `copyJob.mode` | `copy` (copy then verify; Job `<fullname>-copy`) or `verify` (`--verify-only`; Job `<fullname>-copy-verify`) | `copy` |
| `copyJob.image.{repository,tag,pullPolicy}` | PR 8's image with the copy script. Repository and tag are required when enabled (the render fails while either is empty) | `ghcr.io/jfms7s/firstdime-migrate-sqlite-to-pg`, `""`, `IfNotPresent` |
| `copyJob.command` | The copy script's command | `node scripts/migrate-sqlite-to-pg/index.mjs` |
| `copyJob.sourceUrl` | libSQL URL of the sqld being copied (`libsql://`, `http(s)://`, `ws(s)://`); empty = this chart's own sqld, which then needs `sqld.enabled: true` | `""` |
| `copyJob.sourceTokenSecret.{name,key}` | Secret key with sqld's auth token (required when enabled), exposed as `COPY_SOURCE_TOKEN` | `""` |
| `copyJob.waitTimeoutSeconds` | Seconds each init container waits (Postgres, then the source) before failing the Job | `600` |
| `copyJob.activeDeadlineSeconds` / `copyJob.resources` / `copyJob.nodeSelector` / `copyJob.tolerations` / `copyJob.affinity` | Deadline, requests/limits (`256Mi` / `1Gi`) and pod placement | `3600` |
| `api.replicas` / `web.replicas` | Whole number, 0 or more; 0 stops it (cutover) | `1` |
| `worker.replicas` / `bankSync.replicas` | 0 or 1 (never two); 0 stops it (cutover) | `1` |
| `worker.jobsEnabled` | `WORKER_JOBS_ENABLED`: `false` runs no scheduled job and no outbound runner (webhooks, email, notifications) while the relay and the event consumers keep running. Must be a boolean | `true` |
| `sqld.enabled` | Deploy the legacy sqld (copy source during the cutover window; rollback). The api and worker never connect to it | `false` |
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

Memory requests and limits are set for a Raspberry Pi environment (4 GB):

```yaml
postgres:
  resources:
    requests:
      memory: 256Mi
    limits:
      memory: 512Mi

backup:
  resources:
    requests:
      memory: 64Mi
    limits:
      memory: 256Mi

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

### Block storage (RWO PVCs) for NATS, Frankfurter, bank-sync and the legacy sqld

Postgres has its own claim (see [Postgres](#postgres)). NATS, Frankfurter, bank-sync and sqld (when enabled) each run as a single `Recreate` Deployment, so all can sit on a ReadWriteOnce
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

## Postgres

The api and the worker run on Postgres 18. The chart renders a single-replica StatefulSet (`<fullname>-postgres`) and a Service of the same name, on a ReadWriteOnce block-storage (iSCSI) claim, never NFS.

- **Secret**: `postgres.existingSecret` (required) names a Secret with `POSTGRES_PASSWORD` (read by initdb on the first start only: changing it later does not change the database's password) and `DATABASE_URL`, which everything else reads: the api, worker, backup and copy Job. The expected URL is `postgres://firstdime:<url-encoded password>@<fullname>-postgres:5432/firstdime`.
- **Collation and time zone**: initdb runs with `--locale=C --encoding=UTF8` (text sorts by bytes, as SQLite's BINARY did) and the server runs in UTC.
- **Claim**: `data-<fullname>-postgres-0`, kept on uninstall (`persistentVolumeClaimRetentionPolicy: Retain`, `helm.sh/resource-policy: keep`, and Argo CD `Prune=false,Delete=false`). The volumeClaimTemplate is immutable, so changing `postgres.storageClass` or `postgres.size` makes Argo CD fail the sync. `kubectl delete statefulset <fullname>-postgres --cascade=orphan` only clears that error: the recreated StatefulSet adopts the existing pod and claim, so neither size nor class changes. A size change needs a manual PVC patch (if the storage class allows expansion); a class change needs a dump and a restore onto a new claim.
- **Resources**: 256Mi requested, 512Mi limit, `shared_buffers: 128MB` and `max_connections: 30`, sized for a 4 GB Pi.
- **`database.*` is gone**: `database.url` and `database.authToken` were removed in 0.10.0. Passing a `database` key fails the render.

## Backups

With `postgres.enabled` and `backup.enabled`, a CronJob (`<fullname>-postgres-backup`) runs `pg_dump --format=custom` nightly (`backup.schedule`, UTC, default 02:30) into an NFS export (`backup.nfs.server`, `backup.nfs.path`).

- **Files**: `firstdime-<UTC timestamp>.dump`, e.g. `firstdime-20261107T023000Z.dump`.
- **Safety**: the dump is written to `.dump.tmp`, checked with `pg_restore --list`, and only then renamed into place. A failed dump exits non-zero, removes its partial file and prunes nothing.
- **Retention**: after each good dump, all but the newest `backup.retainCount` (default 14) files are deleted.
- **Owner action, once**: create the directory on the NAS as root before the first run, owned by the backup uid (999) with mode 0700 (`chown 999:999`, `chmod 0700`). `fsGroup` is not applied on NFS and a root-squashed export can't be written by the pod.
- **Failed Jobs** are removed after a day (`ttlSecondsAfterFinished: 86400`) so `KubeJobFailed` stops firing.

Restore into a throwaway database first (never `--clean` against a URL you did not type out):

```bash
psql "postgres://firstdime:<password>@<host>:5432/firstdime" -c "CREATE DATABASE firstdime_restore_test"
pg_restore --no-owner --exit-on-error --single-transaction \
  -d "postgres://firstdime:<password>@<host>:5432/firstdime_restore_test" firstdime-20261107T023000Z.dump
```

Restoring over production is a deliberate, separate step: scale the api and worker to 0 first.

Attachments live on a separate volume and need their own backup; the dump and the attachments should be taken together.

## Copy Job

`copyJob.enabled: true` renders a one-shot Job that runs First Dime's copy script: it copies the legacy sqld database into the (empty) Postgres and verifies the result, as `<command> --source <libsql url> --source-token-env COPY_SOURCE_TOKEN --target-env DATABASE_URL`.

- **Modes**: `copyJob.mode: copy` (Job `<fullname>-copy`) passes `--migrate` (applies the Postgres baseline first, since the api is at 0 during the copy), copies, then verifies. `verify` (Job `<fullname>-copy-verify`) passes `--verify-only` and writes nothing. The two flags are mutually exclusive.
- **Source**: `copyJob.sourceUrl`, or this chart's sqld (`http://<fullname>-sqld:8080`) when empty, which needs `sqld.enabled: true`. The token comes from `copyJob.sourceTokenSecret`.
- **Waits**: two init containers run first, each bounded by `copyJob.waitTimeoutSeconds` (default 600): `wait-for-postgres` (`pg_isready`) and `wait-for-source` (a TCP connect to the source host and port). Past the deadline the Job fails before the copy starts.
- **Image**: PR 8's own image (`copyJob.image.repository`, default `ghcr.io/jfms7s/firstdime-migrate-sqlite-to-pg`; the api image drops `@libsql/client`); `copyJob.image.tag` is required.
- **One-shot**: a plain Job, not an Argo CD hook, with `backoffLimit: 0` and no TTL (Argo CD would re-create a deleted Job and copy again). To re-run, delete the Job. Set `copyJob.enabled: false` after the cutover to remove it.
- **Immutable pod template**: changing anything under `copyJob.*` (image, resources, sourceUrl, command, waitTimeoutSeconds), or `postgres.image` (init container), `postgres.existingSecret` or `imagePullSecrets`, while `copyJob.enabled` is true fails the Argo CD sync on that Job (no re-run, just a failed sync). Delete the Job first or set `enabled: false`, and disable it after the cutover.

## sqld (legacy)

sqld is kept only for the move to Postgres: it is the copy source during the cutover window, and a rollback runs on its volume. It is off by default (`sqld.enabled: false`) and the api and worker no longer connect to it. Its persistence settings are unchanged; the sections on its write lock below apply only while it is enabled.

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

- **At most one replica (`bankSync.replicas`: 0 or 1), `Recreate`** (hardcoded): bank-sync keeps SQLite and in-memory admin sessions, and its
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

Applies only while `sqld.enabled` is true. libsql-server 0.24.33 serialises writers through its own write-lock queue, and a checkpoint or a
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

**Important**: The Postgres dumps and the attachments volume must be backed up together to ensure consistency.

1. **Postgres**: the nightly `pg_dump` files on NFS at `backup.nfs.path` (see [Backups](#backups)); the live data is on the iSCSI claim `data-<fullname>-postgres-0`
2. **Attachments**: Stored on NFS at `/volume1/k8s/volumes/firstdime/attachments`
3. **NATS data**: Stored on NFS at `/volume1/k8s/volumes/firstdime/nats`

Back up the dump directory, the attachments and the NATS directory as a single unit, using your NFS storage's snapshot or backup solution.

Frankfurter's data (when enabled) needs no backup: it re-downloads everything from the central banks. bank-sync keeps its own SQLite claim.

## Upgrading from 0.9.x

0.10.0 moves the api and worker from sqld to Postgres. Breaking changes:

- `database.url` and `database.authToken` are removed, and passing `database` fails the render. The api and worker read `DATABASE_URL` from `postgres.existingSecret`, which is now required.
- `sqld.enabled` now defaults to `false`. Set it to `true` for the cutover window (copy source, rollback), and back to `false` after.
- New `worker.jobsEnabled` (`WORKER_JOBS_ENABLED`, default `true`) and replicas that honour 0: `api.replicas` and `web.replicas` render as set (0 stops them), `worker.replicas` and `bankSync.replicas` are 0 or 1.
- New `backup.nfs.server` / `backup.nfs.path` are required while the backup CronJob is enabled.

The sqld claim `<fullname>-sqld-data` is untouched: it is still rendered while `sqld.persistence.claim` is set, and its `Prune=false,Delete=false` and `helm.sh/resource-policy: keep` keep it even when sqld is not enabled. `apps/bank-sync` keeps its own SQLite claim, unchanged.

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
- **postgres** / **backup**: UID 999 (the postgres image user); the backup directory on NFS must be owned by 999
- **nats**: UID 1000
- **web**: UID 101 (nginx-unprivileged)

**Important**: On NFS, Kubernetes `fsGroup` is not applied (NFS ignores it). Ensure the nats and attachments NFS directories are **writable by UID 1000** (the Postgres backup export is different: it must be owned by uid 999, `backup.runAsUser`). For example, on the Synology:
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

- **API**: Can be scaled by increasing `api.replicas`; `0` stops it
- **Web**: Can be scaled by increasing `web.replicas`; `0` stops it
- **Worker**: `worker.replicas` is 0 or 1, never more (it runs the event bus relay and scheduler; multiple replicas would duplicate messages)
- **Postgres**: **Hardcoded to 1 replica** (one server on one RWO volume)
- **NATS**: **Hardcoded to 1 replica** (single broker model; HA would require additional configuration not included in this chart)
- **Frankfurter**: **Hardcoded to 1 replica** (one process per SQLite file)
- **bank-sync**: `bankSync.replicas` is 0 or 1, never more (one process per SQLite file)

## License

See [First Dime](https://github.com/jfms7s/firstdime) for license information.

## Support

For issues, feature requests, or questions:
- [First Dime GitHub](https://github.com/jfms7s/firstdime)
- [Helm Charts GitHub](https://github.com/jfms7s/helm-charts)
