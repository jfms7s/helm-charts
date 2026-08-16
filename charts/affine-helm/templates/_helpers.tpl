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
Render an env var's value/valueFrom body from a {value, valueFrom} map, e.g.
{{- include "affine-helm.credentialEnv" .Values.postgres.password | nindent N }}
valueFrom (a standard corev1 EnvVarSource body, e.g. secretKeyRef) takes
precedence over value when both are set. value defaults to "CHANGE_ME",
since Argo CD does not support Helm's `lookup` function, so -- unlike a
plain `helm install` -- a password can't be safely auto-generated and
persisted across syncs; callers must pin one explicitly.
*/}}
{{- define "affine-helm.credentialEnv" -}}
{{- if .valueFrom -}}
valueFrom: {{- toYaml .valueFrom | nindent 2 }}
{{- else -}}
value: {{ .value | default "CHANGE_ME" | quote }}
{{- end -}}
{{- end -}}
