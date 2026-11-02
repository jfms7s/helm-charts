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
Every credential the chart consumes, as Secret key -> its {value, valueFrom}
map. Fills the dict passed as .out; pass (dict "ctx" $ "out" (dict)).
*/}}
{{- define "patchmon-helm.credentials" -}}
{{- $v := .ctx.Values -}}
{{- $_ := set .out "POSTGRES_PASSWORD" ($v.postgres.password | default dict) -}}
{{- $_ := set .out "REDIS_PASSWORD" ($v.redis.password | default dict) -}}
{{- $_ := set .out "JWT_SECRET" ($v.server.jwtSecret | default dict) -}}
{{- $_ := set .out "SESSION_SECRET" ($v.server.sessionSecret | default dict) -}}
{{- $_ := set .out "AI_ENCRYPTION_KEY" ($v.server.aiEncryptionKey | default dict) -}}
{{- end -}}

{{/*
Name of the chart-owned Secret that holds every credential given as value.
*/}}
{{- define "patchmon-helm.credentialsSecretName" -}}
{{- printf "%s-patchmon-credentials" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
The chart Secret's data: one base64 key per credential given as value (no
valueFrom), sorted. Renders nothing when every credential uses valueFrom.
*/}}
{{- define "patchmon-helm.credentialsSecretData" -}}
{{- $creds := dict -}}
{{- include "patchmon-helm.credentials" (dict "ctx" . "out" $creds) -}}
{{- range $key := keys $creds | sortAlpha -}}
{{- $cred := get $creds $key -}}
{{- if not $cred.valueFrom }}
{{ $key }}: {{ $cred.value | default "CHANGE_ME" | toString | b64enc | quote }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Pod-template annotation that rolls a workload when a credential given as
value changes (the env var points at the chart Secret, so the pod spec itself
would not change). Renders nothing when no credential is given as value.
Include with nindent at the pod template's metadata level.
*/}}
{{- define "patchmon-helm.credentialsChecksum" -}}
{{- with include "patchmon-helm.credentialsSecretData" . -}}
annotations:
  checksum/credentials: {{ sha256sum . }}
{{- end -}}
{{- end -}}

{{/*
Render an env var's valueFrom body for one credential, by its Secret key, e.g.
{{- include "patchmon-helm.credentialEnv" (dict "ctx" $ "key" "POSTGRES_PASSWORD") | nindent N }}
A credential's own valueFrom (a standard corev1 EnvVarSource body, e.g.
secretKeyRef) is passed through; a credential given as value is read from the
chart Secret, so it never appears in a workload spec. Never emits both value
and valueFrom on one EnvVar. Credentials are never generated: Argo CD has no
`lookup`, so a generated value would rotate on every sync.
*/}}
{{- define "patchmon-helm.credentialEnv" -}}
{{- $creds := dict -}}
{{- include "patchmon-helm.credentials" (dict "ctx" .ctx "out" $creds) -}}
{{- if not (hasKey $creds .key) -}}
{{- fail (printf "patchmon-helm: unknown credential key %s" .key) -}}
{{- end -}}
{{- $cred := get $creds .key -}}
{{- if $cred.valueFrom -}}
valueFrom: {{- toYaml $cred.valueFrom | nindent 2 }}
{{- else -}}
valueFrom:
  secretKeyRef:
    name: {{ include "patchmon-helm.credentialsSecretName" .ctx }}
    key: {{ .key }}
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
