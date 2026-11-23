# Vendored chart

This chart is a copy of `synology-csi` 0.11.3 (appVersion v1.3.1) from
https://github.com/christian-schlichtherle/synology-csi-chart, pulled from
https://christian-schlichtherle.github.io/synology-csi-chart and kept unchanged
(Apache-2.0, see `LICENSE`). It is vendored so that a republish upstream cannot
change what Argo CD deploys: only a commit in this repository can.

To update it, re-vendor from upstream. Keep this file, and let `Chart.yaml`'s
`version` follow upstream's:

```bash
helm repo add synology-csi https://christian-schlichtherle.github.io/synology-csi-chart
tmp=$(mktemp -d)
helm pull synology-csi/synology-csi --version <new> --untar --untardir "$tmp"
# replace everything except this file
find charts/synology-csi -mindepth 1 ! -name VENDORED.md -delete
cp -a "$tmp"/synology-csi/. charts/synology-csi/
# check: the only difference from upstream is this file
diff -r "$tmp"/synology-csi charts/synology-csi   # expect only: Only in charts/synology-csi: VENDORED.md
```

Then update the version named in the first paragraph above and in `AGENTS.md`.
