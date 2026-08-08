{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "patchmon-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "server|postgres|redis|guacd" "component" "server|database|cache|rdp-proxy").
*/}}
{{- define "patchmon-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: patchmon
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "patchmon-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from patchmon-helm.labels because
selectors (Deployment matchLabels / Service selector) are immutable after
creation, so this must never gain chart-version-derived keys. Pass
(dict "context" $ "name" "server|postgres|redis|guacd").
*/}}
{{- define "patchmon-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Resolve secret values from values.yaml. Argo CD does not support Helm's
`lookup` function, so -- unlike a plain `helm install` -- these can't be
safely auto-generated and persisted across syncs. Callers must pin them
explicitly; values.yaml ships "CHANGE_ME" placeholders.
*/}}
{{- define "patchmon-helm.postgres.password" -}}
{{- .Values.postgres.password | default "CHANGE_ME" -}}
{{- end -}}

{{- define "patchmon-helm.redis.password" -}}
{{- .Values.redis.password | default "CHANGE_ME" -}}
{{- end -}}

{{- define "patchmon-helm.server.jwtSecret" -}}
{{- .Values.server.jwtSecret | default "CHANGE_ME" -}}
{{- end -}}

{{- define "patchmon-helm.server.sessionSecret" -}}
{{- .Values.server.sessionSecret | default "CHANGE_ME" -}}
{{- end -}}

{{- define "patchmon-helm.server.aiEncryptionKey" -}}
{{- .Values.server.aiEncryptionKey | default "CHANGE_ME" -}}
{{- end -}}
