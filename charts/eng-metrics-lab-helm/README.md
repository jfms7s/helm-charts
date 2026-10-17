# eng-metrics-lab-helm

Deploys eng-metrics-lab, a code-quality reporting stack built on `ghcr.io/jfms7s/quality-report`:

| Part | Kind | Notes |
|---|---|---|
| `<release>-postgres` | Deployment + Service + PVC | Postgres 18, one replica, Recreate; the PVC is kept on uninstall and prune |
| `<release>-migrate` | Job (Argo CD `PostSync` hook) | `quality-collector migrate`: schema and least-privilege roles; `backoffLimit: 6` waits out Postgres startup |
| `<release>-collector` | CronJob | `quality-collector collect`: GitHub artifacts into Postgres; no concurrency, no retries |
| `<release>-backup` | CronJob + PVC | `pg_dump -Fc` to `/backups` on an NFS-backed PVC, written to `.tmp` and renamed only on success (umask 077); dumps older than `backup.keepDays` are pruned even when the dump fails, which still fails the job |

The quality-collector image has no USER and its inherited ENTRYPOINT/CMD are node's, so the chart must set `command: [quality-collector]`; it runs the migrate and collector containers as uid 1000, read-only root, `HOME=/tmp` on an `emptyDir`. Postgres runs as uid 999.

## Secret

`existingSecret` (default `eng-metrics-lab-secrets`) must hold `POSTGRES_PASSWORD`, `QUALITY_WRITER_PASSWORD`, `QUALITY_COLLECTOR_PASSWORD`, `QUALITY_GRAFANA_PASSWORD` and `GITHUB_TOKEN`. The chart never generates a secret. Passwords must be alphanumeric: connection URLs are built with Kubernetes `$(VAR)` expansion, unescaped. `GITHUB_TOKEN` may be absent: its `secretKeyRef` is `optional`, so the collector starts and exits 2 naming the missing variable instead of the pod failing with `CreateContainerConfigError`.

## Values

| Key | Default | Description |
|---|---|---|
| `image.repository` | `ghcr.io/jfms7s/quality-report` | quality-collector image (private) |
| `image.tag` | `0.1.0` | image tag |
| `image.pullPolicy` | `IfNotPresent` | |
| `imagePullSecrets` | `[]` | pull secrets for the migrate and collector pods |
| `existingSecret` | `eng-metrics-lab-secrets` | Secret holding the keys above |
| `nodeSelector` | `{}` | node selector for all four pod specs (Postgres, migrate, collector, backup); the image is amd64-only, so set `kubernetes.io/arch: amd64` |
| `affinity` | `{}` | affinity for all four pod specs |
| `tolerations` | `[]` | tolerations for all four pod specs |
| `postgres.image.repository` | `docker.io/library/postgres` | also used by the backup CronJob (it has `pg_dump`) |
| `postgres.image.tag` | `18-bookworm` | |
| `postgres.image.pullPolicy` | `IfNotPresent` | |
| `postgres.database` | `quality` | database name |
| `postgres.persistence.volume` | `{}` | volume source for the data directory (e.g. `persistentVolumeClaim.claimName`); empty means the chart-created PVC; emptyDir is refused |
| `postgres.persistence.claim.storageClassName` | `synology-iscsi` | the chart creates PVC `<release>-postgres-data` while this is set; clear it to skip |
| `postgres.persistence.claim.size` | `2Gi` | size of the created PVC |
| `postgres.persistence.subPath` | `pgdata` | subdirectory of the volume mounted at `/var/lib/postgresql/data` |
| `postgres.resources` | `{}` | |
| `migrate.activeDeadlineSeconds` | `900` | hard cap on the PostSync migrate Job, so a stuck pod fails the sync instead of hanging it |
| `collector.schedule` | `0 3 * * *` | cron schedule |
| `collector.githubOwner` | `jfms7s` | `QUALITY_GITHUB_OWNER` |
| `collector.githubRepos` | `[replica-sync]` | joined with commas into `QUALITY_GITHUB_REPOS` |
| `collector.lookbackDays` | `3` | `QUALITY_LOOKBACK_DAYS` |
| `collector.resources` | `{}` | also applied to the migrate Job |
| `backup.schedule` | `30 3 * * *` | cron schedule |
| `backup.keepDays` | `30` | dumps older than this are deleted |
| `backup.persistence.volume` | `{}` | volume source for `/backups`; empty means the chart-created PVC |
| `backup.persistence.claim.storageClassName` | `nfs-client` | the chart creates PVC `<release>-backup` while this is set; clear it to skip |
| `backup.persistence.claim.size` | `1Gi` | size of the created PVC |
| `backup.resources` | `{}` | |

Both created PVCs carry `helm.sh/resource-policy: keep` and `argocd.argoproj.io/sync-options: Prune=false,Delete=false`.
