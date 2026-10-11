{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "tompero-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "server" "component" "server|storage").
*/}}
{{- define "tompero-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: tompero
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "tompero-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from tompero-helm.labels because
selectors (Deployment matchLabels / Service selector) are immutable after
creation, so this must never gain chart-version-derived keys. Pass
(dict "context" $ "name" "server").
*/}}
{{- define "tompero-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Render an env var's value/valueFrom body from a {value, valueFrom} map, e.g.
{{- include "tompero-helm.credentialEnv" .Values.server.databaseUrl | nindent N }}
valueFrom (a standard corev1 EnvVarSource body, e.g. secretKeyRef) takes
precedence over value when both are set. value defaults to "CHANGE_ME",
since Argo CD does not support Helm's `lookup` function, so -- unlike a
plain `helm install` -- these can't be safely auto-generated and persisted
across syncs; callers must pin one explicitly.
*/}}
{{- define "tompero-helm.credentialEnv" -}}
{{- if .valueFrom -}}
valueFrom: {{- toYaml .valueFrom | nindent 2 }}
{{- else -}}
value: {{ .value | default "CHANGE_ME" | quote }}
{{- end -}}
{{- end -}}
