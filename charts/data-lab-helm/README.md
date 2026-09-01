# data-lab-helm

Shared infrastructure for the Spark and Flink learning labs, so the exercise
scripts don't each hand-roll namespaces and RBAC:

- **Namespaces + RBAC** for Spark (`spark`) and Flink (`flink`) — a ServiceAccount
  and a scoped, namespaced `Role` per engine (no `ClusterRole`, no wildcards).

The object store the labs read/write over `s3a://` (RustFS, S3-compatible) is
**not** part of this chart — it's a second source in helm-argo-cd's
multi-source `data-lab` Application, pulled directly from RustFS's own chart
repository (`https://charts.rustfs.com`). Bucket creation (`datasets`,
`warehouse`, `checkpoints`) is likewise not part of this chart — see
`terraform-provision/rustfs`.

Datasets are generated and written into `s3a://datasets/…` by the exercise
scripts (`obsidian-vault: learning/engineering/spark/exercises/scripts/seed.sh`),
which run the generator locally.

## Prerequisites

- Kubernetes 1.19+, Helm 3.0+

## Install

```bash
helm install data-lab . --namespace data-lab --create-namespace
```

This chart alone only creates namespaces/RBAC — it does not stand up a
working object store by itself. See helm-argo-cd's `data-lab` Application for
the full picture (this chart + RustFS's chart together).

## Configuration

See [values.yaml](values.yaml) — every parameter is documented inline. Key ones:

| Key | Default | Notes |
|---|---|---|
| `spark.enabled` / `flink.enabled` | `true` | per-engine namespace + RBAC |
