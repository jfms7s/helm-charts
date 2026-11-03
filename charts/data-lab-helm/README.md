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

## Resource names

The Namespaces and ServiceAccounts are named by values, not by the release: Spark jobs submit to Namespace `spark.namespace` (default `spark`) as ServiceAccount `spark.serviceAccount` (default `spark`); Flink likewise with `flink.namespace` / `flink.serviceAccount` (default `flink` / `flink`). Renaming a Namespace value deletes the old Namespace with everything in it.

## Configuration

See [values.yaml](values.yaml) — every parameter is documented inline. Key ones:

| Key | Default | Notes |
|---|---|---|
| `spark.enabled` / `flink.enabled` | `true` | per-engine namespace + RBAC |
| `podSecurity.enforce` | `baseline` | Pod Security Admission level enforced on both namespaces (`privileged`, `baseline`, `restricted`; `""` skips it). Not `restricted`: lab pods mount inline `nfs:` volumes |
| `podSecurity.warn` / `podSecurity.audit` | `restricted` | levels reported as client warnings / in the audit log only |

### Pod Security

Both engine ServiceAccounts can create pods in their namespace, so each
Namespace carries `pod-security.kubernetes.io/enforce: baseline`: a leaked
token or a lab job cannot start a privileged, host-namespace or `hostPath`
pod. Pods already running are not evicted when the label is added; a
non-compliant pod is rejected at its next creation.

### Namespace deletion

Both Namespaces carry `helm.sh/resource-policy: keep` and
`argocd.argoproj.io/sync-options: Prune=false,Delete=false`: disabling an
engine, renaming its namespace, `helm uninstall` or deleting the Argo CD
Application leaves the Namespace (and its PVCs, Secrets and running jobs)
in place. Argo CD then shows it as out of sync rather than pruning it.
Deleting a lab Namespace is a manual `kubectl delete namespace <name>`.
