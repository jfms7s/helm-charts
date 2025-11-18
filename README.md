# Helm Charts

A collection of Helm charts for Kubernetes applications.

## Available Charts

### Common
A generic application chart that provides a standardized template for deploying containerized applications to Kubernetes.

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

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test your changes with `helm lint` and `helm template`
5. Submit a pull request

## License

This project is licensed under the MIT License.