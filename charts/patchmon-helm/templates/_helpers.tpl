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

{{/*
Name of the Secret backing Postgres/Redis/server credentials. Each defaults
to this chart's own auto-generated Secret; set the matching
<resource>.existingSecret value to point at a pre-existing Secret instead
(e.g. one synced by an external secrets manager) without any other template
changes.
*/}}
{{- define "patchmon-helm.postgres.secretName" -}}
{{- .Values.postgres.existingSecret | default (printf "%s-patchmon-postgres" .Release.Name) -}}
{{- end -}}

{{- define "patchmon-helm.postgres.secretKey" -}}
{{- .Values.postgres.existingSecretPasswordKey | default "postgres-password" -}}
{{- end -}}

{{- define "patchmon-helm.redis.secretName" -}}
{{- .Values.redis.existingSecret | default (printf "%s-patchmon-redis" .Release.Name) -}}
{{- end -}}

{{- define "patchmon-helm.redis.secretKey" -}}
{{- .Values.redis.existingSecretPasswordKey | default "redis-password" -}}
{{- end -}}

{{- define "patchmon-helm.server.secretName" -}}
{{- .Values.server.existingSecret | default (printf "%s-patchmon-server" .Release.Name) -}}
{{- end -}}

{{- define "patchmon-helm.server.jwtSecretKey" -}}
{{- .Values.server.existingSecretJwtKey | default "jwt-secret" -}}
{{- end -}}

{{- define "patchmon-helm.server.sessionSecretKey" -}}
{{- .Values.server.existingSecretSessionKey | default "session-secret" -}}
{{- end -}}

{{- define "patchmon-helm.server.aiEncryptionKeyKey" -}}
{{- .Values.server.existingSecretAiEncryptionKey | default "ai-encryption-key" -}}
{{- end -}}
