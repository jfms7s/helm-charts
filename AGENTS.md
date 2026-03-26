# AGENTS.md

This is a Helm charts repository containing application-specific and shared charts.

## Project Structure

```
helm-charts/
├── charts/
│   ├── affine-helm/     # Chart for Affine application
│   └── common/          # Generic chart for multiple applications
└── .github/workflows/   # CI/CD pipelines
```

## Charts

### affine-helm
Application-specific chart for deploying the [Affine](https://affine.pro/) workspace application. Includes:
- Affine main deployment
- PostgreSQL database
- Redis cache
- Ingress configuration
- Migration job

### common
Reusable chart for deploying containerized applications. Provides:
- Deployment template
- Service configuration
- Ingress support
- ServiceAccount management

## Development Commands

```bash
# Lint a chart
helm lint charts/affine-helm
helm lint charts/common

# Template a chart
helm template my-release charts/affine-helm
helm template my-release charts/common

# Package a chart
helm package charts/affine-helm
helm package charts/common

# Run tests
helm lint charts/*
```

## Release Process

Charts are automatically released via GitHub Actions when version tags are pushed.
