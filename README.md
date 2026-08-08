# Helm Charts

A collection of Helm charts for Kubernetes applications.

## Available Charts

### Common
A generic application chart that provides a standardized template for deploying containerized applications to Kubernetes.

### affine-helm
Deploys [Affine](https://affine.pro/), a self-hosted workspace/collaboration app, with its Postgres (pgvector) database and Redis cache. See [charts/affine-helm/README.md](charts/affine-helm/README.md).

### patchmon-helm
Deploys [PatchMon](https://patchmon.net/), a self-hosted Linux patch management platform, with its Postgres database, Redis cache, and guacd (in-browser RDP) sidecar. See [charts/patchmon-helm/README.md](charts/patchmon-helm/README.md).

## Installation

Add the repository:

```bash
helm repo add jfms7s https://jfms7s.github.io/helm-charts
helm repo update
```

### Install the Common Chart

```bash
helm install my-release jfms7s/common
```

### Customize Installation

Create a `values.yaml` file to customize the deployment:

```yaml
deploy:
  image:
    repository: nginx
    tag: latest
  containerPorts:
    http: 80
ingress:
  enabled: true
  hostname: example.com
```

Then install with custom values:

```bash
helm install my-release jfms7s/common -f values.yaml
```

## Uninstall

```bash
helm delete my-release
```

## Development

### Linting

```bash
helm lint charts/common
```

### Template Testing

```bash
helm template my-release charts/common
```

### Package Chart

```bash
helm package charts/common
```

Or use the [Makefile](Makefile) (`make help`) to lint, template, and validate every chart in the repo at once — the same checks CI runs.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test your changes with `helm lint` and `helm template`
5. Submit a pull request

## License

This project is licensed under the MIT License.