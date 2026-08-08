{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "affine-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "affine|postgres|redis" "component" "server|database|cache").
*/}}
{{- define "affine-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: affine
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "affine-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from affine-helm.labels because
selectors (Deployment matchLabels / Service selector) are immutable after
creation, so this must never gain chart-version-derived keys. Pass
(dict "context" $ "name" "affine|postgres|redis").
*/}}
{{- define "affine-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Resolve the Postgres password from values. Argo CD does not support Helm's
`lookup` function, so -- unlike a plain `helm install` -- a password can't be
safely auto-generated and persisted across syncs. Callers must pin one
explicitly; values.yaml ships "CHANGE_ME" as a placeholder.
*/}}
{{- define "affine-helm.postgres.password" -}}
{{- .Values.postgres.password | default "CHANGE_ME" -}}
{{- end -}}
