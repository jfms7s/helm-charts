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
{{ include "patchmon-helm.podLabels" . }}
helm.sh/chart: {{ include "patchmon-helm.chart" .context }}
{{- end -}}

{{/*
Pod-template labels: the standard labels minus helm.sh/chart, so a chart
release that does not change a workload's spec does not restart its pods.
Same arguments as patchmon-helm.labels.
*/}}
{{- define "patchmon-helm.podLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: patchmon
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
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
Render an env var's value/valueFrom body from a {value, valueFrom} map, e.g.
{{- include "patchmon-helm.credentialEnv" .Values.postgres.password | nindent N }}
valueFrom (a standard corev1 EnvVarSource body, e.g. secretKeyRef) takes
precedence over value when both are set. value defaults to "CHANGE_ME",
since Argo CD does not support Helm's `lookup` function, so -- unlike a
plain `helm install` -- these can't be safely auto-generated and persisted
across syncs; callers must pin one explicitly.
*/}}
{{- define "patchmon-helm.credentialEnv" -}}
{{- if .valueFrom -}}
valueFrom: {{- toYaml .valueFrom | nindent 2 }}
{{- else -}}
value: {{ .value | default "CHANGE_ME" | quote }}
{{- end -}}
{{- end -}}

{{/*
Render-time guard for one credential in the {value, valueFrom} shape: fails
unless valueFrom is set or value is non-empty and not the CHANGE_ME
placeholder. A null or missing key counts as unset (this repo is public, so a
placeholder secret is a known secret). Pass
(dict "credentialName" "server.jwtSecret" "credential" .Values.server.jwtSecret).
*/}}
{{- define "patchmon-helm.requiredCredential" -}}
{{- $cred := .credential | default dict -}}
{{- $value := trim (toString ($cred.value | default "")) -}}
{{- if and (or (eq $value "") (eq $value "CHANGE_ME")) (not $cred.valueFrom) -}}
  {{- fail (printf "patchmon-helm: %s must be set (value or valueFrom); the CHANGE_ME placeholder is not accepted" .credentialName) -}}
{{- end -}}
{{- end -}}

{{/*
Every required credential, checked at the top of each template that consumes
one, so no template renders on its own with a placeholder. Renders nothing.
*/}}
{{- define "patchmon-helm.validate" -}}
{{- $ := . -}}
{{- include "patchmon-helm.requiredCredential" (dict "credentialName" "server.jwtSecret" "credential" $.Values.server.jwtSecret) }}
{{- include "patchmon-helm.requiredCredential" (dict "credentialName" "server.sessionSecret" "credential" $.Values.server.sessionSecret) }}
{{- include "patchmon-helm.requiredCredential" (dict "credentialName" "server.aiEncryptionKey" "credential" $.Values.server.aiEncryptionKey) }}
{{- include "patchmon-helm.requiredCredential" (dict "credentialName" "postgres.password" "credential" $.Values.postgres.password) }}
{{- include "patchmon-helm.requiredCredential" (dict "credentialName" "redis.password" "credential" $.Values.redis.password) }}
{{- end -}}
