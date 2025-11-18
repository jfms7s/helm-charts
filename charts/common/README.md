# Common Chart

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

| Parameter | Description | Default |
|-----------|-------------|---------|
| `nameOverride` | String to partially override common.names.name | `""` |
| `fullnameOverride` | String to fully override common.names.fullname | `""` |
| `commonLabels` | Labels to add to all deployed objects | `{}` |
| `commonAnnotations` | Annotations to add to all deployed objects | `{}` |
| `deploy.image.repository` | Container image repository | `""` |
| `deploy.image.tag` | Container image tag | `""` |
| `deploy.image.pullPolicy` | Container image pull policy | `IfNotPresent` |
| `deploy.containerPorts.http` | HTTP container port | `0` |
| `deploy.extraVolumes` | Additional volumes for the pod | `[]` |
| `deploy.extraVolumeMounts` | Additional volume mounts for the container | `[]` |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `"traefik"` |
| `ingress.pathType` | Ingress path type | `ImplementationSpecific` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hostname` | Ingress hostname | `""` |
| `ingress.path` | Ingress path | `/` |

### Example Configuration

```yaml
deploy:
  image:
    repository: nginx
    tag: "1.21"
    pullPolicy: Always
  containerPorts:
    http: 80
  extraVolumes:
    - name: config
      configMap:
        name: my-config
  extraVolumeMounts:
    - name: config
      mountPath: /etc/config

ingress:
  enabled: true
  className: nginx
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
  hostname: example.com
  path: /app
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
