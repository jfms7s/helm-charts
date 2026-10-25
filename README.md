# Helm Charts

A collection of Helm charts for Kubernetes applications.

## Available Charts

### Common
A generic application chart that provides a standardized template for deploying containerized applications to Kubernetes.

### affine-helm
Deploys [Affine](https://affine.pro/), a self-hosted workspace/collaboration app, with its Postgres (pgvector) database and Redis cache. See [charts/affine-helm/README.md](charts/affine-helm/README.md).

### firstdime-helm
Deploys [First Dime](https://github.com/jfms7s/firstdime) (Number One Dime), a personal finance application, with its API server, web UI frontend, async worker, NATS (JetStream) message bus, an optional Frankfurter exchange-rate API, and optional Enable Banking bank sync (bank-sync). See [charts/firstdime-helm/README.md](charts/firstdime-helm/README.md).

### patchmon-helm
Deploys [PatchMon](https://patchmon.net/), a self-hosted Linux patch management platform, with its Postgres database, Redis cache, and guacd (in-browser RDP) sidecar. See [charts/patchmon-helm/README.md](charts/patchmon-helm/README.md).

### meiun-helm
Deploys [meiun](https://github.com/jfms7s/meiun), a village sim with LLM-driven villagers: an API, a worker, a static PWA and an optional pgvector Postgres behind one path-split Ingress host. See [charts/meiun-helm/README.md](charts/meiun-helm/README.md).

### tompero-helm
Deploys [Chez Tomperô](https://github.com/jfms7s/tompero), a self-hosted recipe manager and meal planner, as a single server container with SQLite (or an external Postgres). See [charts/tompero-helm/README.md](charts/tompero-helm/README.md).

### padel-score-helm
Deploys [padel-score](https://github.com/jfms7s/padel-score), a padel match scorer with live spectator links, as a single server container with SQLite. See [charts/padel-score-helm/README.md](charts/padel-score-helm/README.md).

### ticket-live-event-scanner-helm
Deploys [Ticket Live Event Scanner](https://github.com/jfms7s/ticket-live-event-scanner), a scraper/notifier pipeline for ticketline.pt event listings, with its in-cluster NATS (JetStream) message bus. See [charts/ticket-live-event-scanner-helm/README.md](charts/ticket-live-event-scanner-helm/README.md).

### eng-metrics-lab-helm
Deploys eng-metrics-lab, a code-quality reporting stack: a small Postgres, a PostSync migrate Job, a nightly GitHub collector CronJob and a nightly `pg_dump` backup CronJob to NFS. See [charts/eng-metrics-lab-helm/README.md](charts/eng-metrics-lab-helm/README.md).

### data-lab-helm
Shared infrastructure for the Spark and Flink learning labs: `spark`/`flink` namespaces with scoped RBAC and an NFS-backed MinIO object store that both a local Spark driver and in-cluster executors reach over `s3a://`. See [charts/data-lab-helm/README.md](charts/data-lab-helm/README.md).

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

### Unit Testing

Each chart has [helm-unittest](https://github.com/helm-unittest/helm-unittest) coverage in `charts/*/tests/` that asserts on rendered manifests (labels, conditionals, secrets, etc.):

```bash
make helm-unittest                        # every chart
make helm-unittest HELM_CHART=common      # one chart
```

Or use the [Makefile](Makefile) (`make help`) to lint, template, validate, and unit-test every chart in the repo at once — the same checks CI runs.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test your changes with `helm lint` and `helm template`
5. Submit a pull request

## License

This project is licensed under the MIT License.