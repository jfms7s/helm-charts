# Common Chart

> **Scope limit:** one Deployment per release (the app container plus init containers and sidecars), its Service, an optional Ingress, PVCs, chart-owned ConfigMaps, an optional ServiceMonitor and a ServiceAccount. StatefulSets, CronJobs, Jobs, a second controller and free-form `extraObjects` are out of scope: such an app gets its own chart or uses bjw-s `app-template` (see "Choosing a composition model" in the repo's `AGENTS.md`).

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

Since 0.10.0 the chart ships a `values.schema.json`: an unknown key under `deploy`, `deploy.image`, `deploy.serviceAccount`, a `configMaps` entry, `service` or `ingress` (a typo such as `deploy.volumeMount` or `deploy.extraVolumes`) fails the render instead of being silently ignored. Kubernetes-shaped values (`resources`, probes, `volumes`, `env`, ...) are passed through as-is and not checked inside. `service.enabled` is accepted but ignored (the Service is always rendered); drop it from your values.

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nameOverride` | String to partially override common.names.name | `""` |
| `fullnameOverride` | String to fully override common.names.fullname | `""` |
| `commonAnnotations` | Annotations added to the pod template, merged with `deploy.podAnnotations`; no `annotations:` key renders when every source is empty (common >= 0.11.0; older versions render `annotations: {}`) | `{}` |
| `configMaps` | Chart-owned ConfigMaps keyed by name suffix, each `{data: {<file>: <string>}}`: renders a ConfigMap `<fullname>-<key>` with the chart labels and a `checksum/config-<key>` pod annotation (sha256 of `data`), so a data change rolls the pod. Keys are DNS labels of at most 56 characters (common >= 0.11.0) | `{}` |
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
| `deploy.hostNetwork` | Run the pod in the node's network namespace, for LAN discovery (mDNS/SSDP); ports bind on the node, so pin it with `nodeSelector` (common >= 0.13.0) | `false` |
| `deploy.dnsPolicy` | Pod DNS policy; empty is the Kubernetes default, or `ClusterFirstWithHostNet` when `hostNetwork` is true so cluster DNS keeps working (common >= 0.13.0) | `""` |
| `deploy.nodeSelector` | Node labels the pod must match, rendered verbatim (common >= 0.7.0; older versions ignore it silently) | `{}` |
| `deploy.affinity` | Pod/node affinity, rendered verbatim (common >= 0.7.0; older versions ignore it silently) | `{}` |
| `deploy.tolerations` | Tolerations for tainted nodes, rendered verbatim (common >= 0.7.0; older versions ignore it silently) | `[]` |
| `deploy.volumes` | Pod volumes, rendered verbatim | `[]` |
| `deploy.volumeMounts` | Container volume mounts, rendered verbatim | `[]` |
| `deploy.persistentVolumeClaims` | PVCs to create: `{name, storageClassName, size, accessModes}` (class and size required, accessModes defaults to `[ReadWriteOnce]`). Kept on uninstall/prune (`helm.sh/resource-policy: keep`, Argo CD `Prune=false,Delete=false`); reference one from `deploy.volumes` via `persistentVolumeClaim.claimName` | `[]` |
| `deploy.initContainers` | Init containers, rendered verbatim | `[]` |
| `deploy.extraContainers` | Sidecar containers, rendered verbatim after the app container (common >= 0.11.0) | `[]` |
| `deploy.podAnnotations` | Pod-template annotations, merged over `commonAnnotations` (a shared key takes this value; common >= 0.11.0) | `{}` |
| `deploy.env` | Container environment variables (`{name, value}` or `{name, valueFrom}`), rendered verbatim | `[]` |
| `deploy.command` | Override the image's ENTRYPOINT (exec form) | `[]` |
| `deploy.args` | Override the image's CMD (exec form) | `[]` |
| `deploy.containerPorts` | Container ports keyed by IANA port name: scalar `http: 8080` or map `http: {port: 8080, protocol: TCP}` (protocol defaults to TCP) | `{}` |
| `deploy.livenessProbe` / `deploy.readinessProbe` / `deploy.startupProbe` | Container probes, rendered verbatim | `{}` |
| `service.type` | Service type | `ClusterIP` |
| `service.ports` | Service ports: scalar `http: 80` or map `https: {port: 443, targetPort: 8443, protocol: TCP}` | `{"http": 80}` |
| `service.annotations` | Service annotations | `{}` |
| `service.labels` | Service labels | `{}` |
| `serviceMonitor.enabled` | Render a Prometheus Operator ServiceMonitor for the Service; nothing renders unless the cluster has the `monitoring.coreos.com/v1` API (common >= 0.12.0) | `false` |
| `serviceMonitor.port` | Name of the `service.ports` key to scrape (required when enabled; the render fails if it is not a key) | `""` |
| `serviceMonitor.path` | Metrics path | `/metrics` |
| `serviceMonitor.interval` / `serviceMonitor.scrapeTimeout` | Scrape interval and timeout (empty = Prometheus default) | `""` |
| `serviceMonitor.labels` | Extra labels on the ServiceMonitor | `{}` |
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

### Sidecar and chart-owned ConfigMap

```yaml
fullnameOverride: homepage
configMaps:
  config:                   # ConfigMap homepage-config, pod annotation checksum/config-config
    data:
      settings.yaml: |
        title: Home
deploy:
  podAnnotations:
    reloader.stakater.com/auto: "true"
  extraContainers:
    - name: exporter
      image: ghcr.io/example/exporter:1.0.0
      ports:
        - name: metrics
          containerPort: 9100
  volumes:
    - name: config
      configMap:
        name: homepage-config
  volumeMounts:
    - name: config
      mountPath: /app/config
```

## Resource names

Consumers wire other apps to these names, so they are part of the chart's interface (unit tests pin them). `<fullname>` is `fullnameOverride` if set; else the release name when it already contains `nameOverride` (default `common`); else `<release>-<nameOverride>`. Every name is cut to 63 characters.

| Object | Name | Example: namespace `tools`, `fullnameOverride: my-app` |
|---|---|---|
| Service | `<namespace>-<fullname>` | `tools-my-app`, DNS `tools-my-app.tools.svc` |
| Ingress | `<fullname>`, backend is the Service above | `my-app` |
| Deployment | `<fullname>` | `my-app` |
| ServiceAccount (`deploy.serviceAccount.create`) | `deploy.serviceAccount.name`, else `<fullname>` | `my-app` |
| PersistentVolumeClaim | each `deploy.persistentVolumeClaims[].name`, verbatim | |
| ConfigMap | `<fullname>-<key>` per `configMaps` key | `my-app-config` |
| ServiceMonitor | `<fullname>` | `my-app` |

## Deployment

This chart creates the following Kubernetes resources:

- Deployment
- Service
- Ingress (if enabled)
- PersistentVolumeClaims (`deploy.persistentVolumeClaims`)
- ConfigMaps (`configMaps`)
- ServiceMonitor (`serviceMonitor.enabled`, needs the Prometheus Operator CRD)
- ServiceAccount (`deploy.serviceAccount.create`)

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
