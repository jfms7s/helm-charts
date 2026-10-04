# Budget Manager Helm Chart

A Kubernetes Helm chart for deploying [Budget Manager](https://github.com/jfms7s/budget-manager), a personal finance application.

## Overview

This chart deploys a complete Budget Manager stack on Kubernetes, including:

- **API Server**: Node.js Express API on port 3000 (Deployment + Service + Ingress)
- **Web Frontend**: Nginx static file server on port 8080 (Deployment + Service + Ingress)
- **Worker**: Async task processor, scheduler, and event bus relay (Deployment)
- **Database (sqld)**: LibSQL server (Deployment + Service, enabled by default, strategy: Recreate)
- **NATS JetStream**: In-cluster message bus for webhooks and events (Deployment + Service)

The application stores user attachments in a shared volume. By default, the chart deploys an in-cluster LibSQL database; you can optionally disable it and point to an external Turso database instead.

## Prerequisites

1. Kubernetes 1.24+
2. Helm 3.0+
3. For production: shared (RWX) storage (NFS recommended) for attachments, NATS data, and sqld database file (if sqld.enabled: true)
4. Optional: external Turso database URL and token (if sqld.enabled: false)

## Installation

### 1. Create a namespace

```bash
kubectl create namespace budget-manager
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
        name: budget-manager-secrets
        key: db-auth-token
sessionCookieSecret:
  valueFrom:
    secretKeyRef:
      name: budget-manager-secrets
      key: session-cookie-secret
appEncryptionKey:
  valueFrom:
    secretKeyRef:
      name: budget-manager-secrets
      key: app-encryption-key
```

**Option B: Create secrets manually**

```bash
kubectl create secret generic budget-manager-secrets \
  --from-literal=db-auth-token=<your-token> \
  --from-literal=session-cookie-secret=<your-secret> \
  --from-literal=app-encryption-key=<your-key> \
  -n budget-manager
```

### 3. Configure values

Create a `values-budget-manager.yaml` file with your environment-specific settings:

```yaml
database:
  url: "http://budget-manager-libsql:8080"  # or your Turso URL
  authToken:
    valueFrom:
      secretKeyRef:
        name: budget-manager-secrets
        key: db-auth-token

sessionCookieSecret:
  valueFrom:
    secretKeyRef:
      name: budget-manager-secrets
      key: session-cookie-secret

appEncryptionKey:
  valueFrom:
    secretKeyRef:
      name: budget-manager-secrets
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
      path: /volume1/k8s/volumes/budget-manager/attachments

nats:
  persistence:
    volume:
      nfs:
        server: 192.168.1.10
        path: /volume1/k8s/volumes/budget-manager/nats
```

### 4. Install the chart

```bash
helm install budget-manager ./budget-manager-helm \
  -n budget-manager \
  -f values-budget-manager.yaml
```

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
| `sqld.persistence.claim` / `nats.persistence.claim` | `{storageClassName, size}`: when the class is set, render a PVC `<release>-budget-manager-<sqld\|nats>-data` (RWO, kept on uninstall/prune); point `persistence.volume` at it via `persistentVolumeClaim.claimName` | unset |
| `sqld.persistence.subPath` / `nats.persistence.subPath` | Subdirectory of the volume to mount as the data dir (use on block-backed PVCs to keep ext4's `lost+found` out of it) | `""` |

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

### Block storage (RWO PVCs) for sqld and NATS

sqld and NATS each run as a single `Recreate` Deployment, so both can sit on a ReadWriteOnce
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
        claimName: budget-manager-budget-manager-sqld-data
```

### Database and Backup Strategy

**Important**: The sqld database file and attachments volume must be backed up together to ensure consistency.

1. **Sqld**: Stored on NFS at `/volume1/k8s/volumes/budget-manager/sqld` (managed by the `common` chart's libsql deployment)
2. **Attachments**: Stored on NFS at `/volume1/k8s/volumes/budget-manager/attachments`
3. **NATS data**: Stored on NFS at `/volume1/k8s/volumes/budget-manager/nats`

Backup all three directories as a single unit, and perform backups regularly using your NFS storage's snapshot or backup solution.

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
helm upgrade budget-manager ./budget-manager-helm \
  -n budget-manager \
  -f values-budget-manager.yaml
```

### Email Notifications

To enable email notifications (e.g., for scheduled reports):

```yaml
smtp:
  url:
    valueFrom:
      secretKeyRef:
        name: budget-manager-secrets
        key: smtp-url
  from:
    valueFrom:
      secretKeyRef:
        name: budget-manager-secrets
        key: smtp-from
```

Then create or update the secret:

```bash
kubectl create secret generic budget-manager-secrets \
  --from-literal=smtp-url='smtp://user:password@smtp.example.com:587' \
  --from-literal=smtp-from='your-email@example.com' \
  -n budget-manager --dry-run=client -o yaml | kubectl apply -f -
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
chmod 1770 /volume1/k8s/volumes/budget-manager/nats
chmod 1770 /volume1/k8s/volumes/budget-manager/attachments
chown 1000:1000 /volume1/k8s/volumes/budget-manager/nats
chown 1000:1000 /volume1/k8s/volumes/budget-manager/attachments
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

## License

See [Budget Manager](https://github.com/jfms7s/budget-manager) for license information.

## Support

For issues, feature requests, or questions:
- [Budget Manager GitHub](https://github.com/jfms7s/budget-manager)
- [Helm Charts GitHub](https://github.com/jfms7s/helm-charts)
