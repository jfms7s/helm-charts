# data-lab-helm

Shared infrastructure for the Spark and Flink learning labs, so the exercise
scripts don't each hand-roll namespaces and RBAC:

- **Namespaces + RBAC** for Spark (`spark`) and Flink (`flink`) — a ServiceAccount
  and a scoped, namespaced `Role` per engine (no `ClusterRole`, no wildcards).
- **MinIO** — a single-node, PVC-backed S3 object store with empty buckets
  (`datasets`, `warehouse`, `checkpoints`). Both a Spark driver running on your
  workstation and the in-cluster executors / Flink TaskManagers reach it over
  `s3a://`, so no host mounts or `--files` shipping are needed. The PVC uses the
  cluster's NFS StorageClass, so NFS backs the store without anything mounting
  NFS directly.

Datasets are generated and written into `s3a://datasets/…` by the exercise
scripts (`obsidian-vault: learning/engineering/spark/exercises/scripts/seed.sh`),
which run the generator locally — the chart just provisions the buckets.

## Prerequisites

- Kubernetes 1.19+, Helm 3.0+
- An RWO-capable StorageClass (default `nfs-client`)

## Install

```bash
helm install data-lab . --namespace data-lab --create-namespace
```

Default `minio.service.type` is `NodePort` (`30900` S3 / `30901` console) so a
local Spark driver can reach MinIO without a port-forward. Switch to `ClusterIP`
if you only submit from inside the cluster.

## Wiring the labs

Spark (`spark-submit` / `pyspark`, driver anywhere):

```
--conf spark.hadoop.fs.s3a.endpoint=http://<node-ip>:30900
--conf spark.hadoop.fs.s3a.path.style.access=true
--conf spark.hadoop.fs.s3a.connection.ssl.enabled=false
--conf spark.hadoop.fs.s3a.access.key=minioadmin
--conf spark.hadoop.fs.s3a.secret.key=minioadmin
--packages org.apache.hadoop:hadoop-aws:3.4.1
```

then read `s3a://datasets/generated-parquet`.

Flink: point `s3.endpoint` at `http://data-lab-minio.data-lab.svc:9000`
and use `s3://` paths for checkpoints / sources.

## Configuration

See [values.yaml](values.yaml) — every parameter is documented inline. Key ones:

| Key | Default | Notes |
|---|---|---|
| `storageClass` | `nfs-client` | backing class for the MinIO PVC |
| `minio.service.type` | `NodePort` | `ClusterIP` if submitting only in-cluster |
| `minio.rootUser` / `minio.rootPassword` | `minioadmin` | lab creds; stored in a Secret |
| `spark.enabled` / `flink.enabled` | `true` | per-engine namespace + RBAC |
| `minio.buckets` | `datasets, warehouse, checkpoints` | created on install/upgrade |
