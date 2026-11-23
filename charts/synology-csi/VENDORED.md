# Vendored chart

This chart is a copy of `synology-csi` 0.11.3 (appVersion v1.3.1) from
https://github.com/christian-schlichtherle/synology-csi-chart, pulled from
https://christian-schlichtherle.github.io/synology-csi-chart and kept unchanged
(Apache-2.0, see `LICENSE`). It is vendored so that a republish upstream cannot
change what Argo CD deploys: only a commit in this repository can.

To update it, pull the new upstream version over this directory, keep this file,
and let `Chart.yaml`'s `version` follow upstream's.
