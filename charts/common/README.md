# Common Chart

> **Scope (frozen):** one single-container Deployment + Service + optional Ingress + PVCs (+ ServiceAccount). Defect fixes only; anything that needs a CronJob, StatefulSet, sidecar, ConfigMap, ServiceMonitor or PDB uses bjw-s `app-template` instead (see "Choosing a composition model" in the repo's `AGENTS.md`).

A generic Helm chart for deploying containerized applications to Kubernetes. This chart provides a standardized template with common configurations for deployments, services, and ingress.

## Prerequisites

- Kubernetes 1.19+
- Helm 3.0+

## Installing the Chart

To install the chart with the release name `my-release`:

```bash
helm install my-release .
```

## Configuration

The following table lists the configurable parameters of the common chart and their default values.

Since 0.10.0 the chart ships a `values.schema.json`: an unknown key under `deploy`, `deploy.image`, `deploy.serviceAccount`, `service` or `ingress` (a typo such as `deploy.volumeMount` or `deploy.extraVolumes`) fails the render instead of being silently ignored. Kubernetes-shaped values (`resources`, probes, `volumes`, `env`, ...) are passed through as-is and not checked inside. `service.enabled` is accepted but ignored (the Service is always rendered); drop it from your values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nameOverride` | String to partially override common.names.name | `""` |
| `fullnameOverride` | String to fully override common.names.fullname | `""` |
| `commonAnnotations` | Annotations added to the pod template | `{}` |
| `deploy.image.repository` | Container image repository (required: the render fails without it) | `""` |
| `deploy.image.tag` | Container image tag (empty renders the repository alone) | `""` |
| `deploy.image.pullPolicy` | Container image pull policy | `IfNotPresent` |
| `deploy.replicas` | Number of Deployment replicas | `1` |
| `deploy.strategy` | Deployment update strategy, rendered verbatim; `type: Recreate` also renders `rollingUpdate: null` so a live RollingUpdate Deployment can be switched in place | `{}` (Kubernetes default, RollingUpdate) |
| `deploy.resources` | Container resource requests and limits | `{}` |
| `deploy.securityContext` | Container securityContext, rendered verbatim | `{}` |
| `deploy.podSecurityContext` | Pod securityContext, rendered verbatim | `{}` |
| `deploy.serviceAccount.create` | Create a ServiceAccount for the pod | `false` |
| `deploy.serviceAccount.name` | ServiceAccount name (with `create`, defaults to the fullname; without it, an existing account to use) | `""` |
| `deploy.serviceAccount.annotations` | Annotations on the created ServiceAccount | `{}` |
| `deploy.nodeSelector` | Node labels the pod must match, rendered verbatim (common >= 0.7.0; older versions ignore it silently) | `{}` |
| `deploy.affinity` | Pod/node affinity, rendered verbatim (common >= 0.7.0; older versions ignore it silently) | `{}` |
| `deploy.tolerations` | Tolerations for tainted nodes, rendered verbatim (common >= 0.7.0; older versions ignore it silently) | `[]` |
| `deploy.volumes` | Pod volumes, rendered verbatim | `[]` |
| `deploy.volumeMounts` | Container volume mounts, rendered verbatim | `[]` |
| `deploy.persistentVolumeClaims` | PVCs to create: `{name, storageClassName, size, accessModes}` (class and size required, accessModes defaults to `[ReadWriteOnce]`). Kept on uninstall/prune (`helm.sh/resource-policy: keep`, Argo CD `Prune=false,Delete=false`); reference one from `deploy.volumes` via `persistentVolumeClaim.claimName` | `[]` |
| `deploy.initContainers` | Init containers, rendered verbatim | `[]` |
| `deploy.env` | Container environment variables (`{name, value}` or `{name, valueFrom}`), rendered verbatim | `[]` |
| `deploy.command` | Override the image's ENTRYPOINT (exec form) | `[]` |
| `deploy.args` | Override the image's CMD (exec form) | `[]` |
| `deploy.containerPorts` | Container ports keyed by IANA port name: scalar `http: 8080` or map `http: {port: 8080, protocol: TCP}` (protocol defaults to TCP) | `{}` |
| `deploy.livenessProbe` / `deploy.readinessProbe` / `deploy.startupProbe` | Container probes, rendered verbatim | `{}` |
| `service.type` | Service type | `ClusterIP` |
| `service.ports` | Service ports: scalar `http: 80` or map `https: {port: 443, targetPort: 8443, protocol: TCP}` | `{"http": 80}` |
| `service.annotations` | Service annotations | `{}` |
| `service.labels` | Service labels | `{}` |
| `ingress.enabled` | Render an Ingress | `false` |
| `ingress.className` | IngressClass name (omitted when empty) | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress hosts, each `{host, paths}`; a path is `{path, pathType, port}`: `pathType` defaults to `Prefix`, and `port` is a Service port name (`http`, rendered as `port.name`) or number (`8080`, rendered as `port.number`), default `80` | `[{host: chart-example.local, paths: [{path: /, pathType: Prefix, port: http}]}]` |
| `ingress.tls` | TLS configuration: `[{secretName, hosts}]` | `[]` |

### Example Configuration

```yaml
deploy:
  image:
    repository: nginx
    tag: "1.21"
    pullPolicy: Always
  volumes:
    - name: config
      configMap:
        name: my-config
  volumeMounts:
    - name: config
      mountPath: /etc/config

service:
  type: ClusterIP
  ports:
    http: 80
    https:
      port: 443
      targetPort: 8443
      protocol: TCP

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hosts:
    - host: example.com
      paths:
        - path: /app
          pathType: Prefix
          port: http
```

### Persistent volume claims

```yaml
deploy:
  persistentVolumeClaims:
    - name: app-data
      storageClassName: synology-iscsi
      size: 2Gi
  strategy:
    type: Recreate          # RWO block volume: never two pods at once
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: app-data
  volumeMounts:
    - name: data
      mountPath: /data
      subPath: data         # keeps ext4's lost+found out of the data dir
```

## Deployment

This chart creates the following Kubernetes resources:

- Deployment
- Service
- Ingress (if enabled)

## Upgrading

To upgrade the release:

```bash
helm upgrade my-release .
```

## Uninstalling

To uninstall the release:

```bash
helm uninstall my-release
```
