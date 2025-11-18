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
| `service.ports` | Service ports configuration | `{"http": 80}` |
| `deploy.extraVolumes` | Additional volumes for the pod | `[]` |
| `deploy.extraVolumeMounts` | Additional volume mounts for the container | `[]` |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `"traefik"` |
| `ingress.pathType` | Ingress path type | `ImplementationSpecific` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `service.type` | Service type | `ClusterIP` |
| `service.annotations` | Service annotations | `{}` |
| `service.labels` | Service labels | `{}` |
| `ingress.enabled` | Enable ingress | `false` |
| `ingress.className` | Ingress class name | `""` |
| `ingress.annotations` | Ingress annotations | `{}` |
| `ingress.hosts` | Ingress host configuration | see values.yaml |
| `ingress.tls` | TLS configuration | `[]` |

### Example Configuration

```yaml
deploy:
  image:
    repository: nginx
    tag: "1.21"
    pullPolicy: Always
  extraVolumes:
    - name: config
      configMap:
        name: my-config
  extraVolumeMounts:
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
