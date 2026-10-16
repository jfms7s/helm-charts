{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "meiun-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base name for every resource: the release name when it already says meiun (release "meiun" -> meiun-api), else
<release>-meiun. 50 characters: the longest suffix, -postgres-data, still fits a 63-character name.
*/}}
{{- define "meiun-helm.fullname" -}}
{{- if contains "meiun" .Release.Name -}}
{{- .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-meiun" .Release.Name | trunc 50 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "api|worker|web|postgres" "component" "...").
*/}}
{{- define "meiun-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: meiun
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "meiun-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels for a component: immutable after creation, so never chart-version-derived. Pass (dict "context" $ "name" "...").
*/}}
{{- define "meiun-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
An env var's value/valueFrom body from a {value, valueFrom} map. valueFrom wins; value defaults to "CHANGE_ME".
*/}}
{{- define "meiun-helm.credentialEnv" -}}
{{- if .valueFrom -}}
valueFrom: {{- toYaml .valueFrom | nindent 2 }}
{{- else -}}
value: {{ .value | default "CHANGE_ME" | quote }}
{{- end -}}
{{- end -}}

{{/*
Whether a {value, valueFrom} map is set (a valueFrom, or a value other than "" and CHANGE_ME).
*/}}
{{- define "meiun-helm.isSet" -}}
{{- if or .valueFrom (and .value (ne .value "CHANGE_ME")) -}}true{{- end -}}
{{- end -}}

{{/*
Every chart-wide render-time guard. The api, worker and postgres templates include it, so no part renders with a
placeholder credential, no host, or a database that would not survive a restart.
*/}}
{{- define "meiun-helm.validate" -}}
{{- $ := . -}}
{{- if not $.Values.host -}}
  {{- fail "meiun-helm: host must be set (the app's one public hostname)" -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" $.Values.host) -}}
  {{- fail (printf "meiun-helm: host must be a bare lower-case hostname, no scheme, port or path (got %q)" $.Values.host) -}}
{{- end -}}
{{- if not (include "meiun-helm.isSet" $.Values.betterAuthSecret) -}}
  {{- fail "meiun-helm: betterAuthSecret must be set (value or valueFrom)" -}}
{{- end -}}
{{- if and (not $.Values.betterAuthSecret.valueFrom) (lt (len ($.Values.betterAuthSecret.value | default "")) 32) -}}
  {{- fail "meiun-helm: betterAuthSecret must be at least 32 characters" -}}
{{- end -}}
{{- if $.Values.postgres.enabled -}}
  {{- if not (include "meiun-helm.isSet" $.Values.postgres.password) -}}
    {{- fail "meiun-helm: postgres.password must be set (value or valueFrom)" -}}
  {{- end -}}
  {{- if or (not $.Values.postgres.persistence.volume) (hasKey $.Values.postgres.persistence.volume "emptyDir") -}}
    {{- fail "meiun-helm: postgres.persistence.volume must be persistent storage, not emptyDir" -}}
  {{- end -}}
{{- else if not $.Values.database.url -}}
  {{- fail "meiun-helm: database.url must be set when postgres.enabled is false" -}}
{{- end -}}
{{- $oidc := list $.Values.oidc.issuer (include "meiun-helm.isSet" $.Values.oidc.clientId) (include "meiun-helm.isSet" $.Values.oidc.clientSecret) | compact | len -}}
{{- if and (ne $oidc 0) (ne $oidc 3) -}}
  {{- fail "meiun-helm: oidc.issuer, oidc.clientId and oidc.clientSecret must be set together, or none" -}}
{{- end -}}
{{- $vapid := list $.Values.vapid.subject (include "meiun-helm.isSet" $.Values.vapid.publicKey) (include "meiun-helm.isSet" $.Values.vapid.privateKey) | compact | len -}}
{{- if and (ne $vapid 0) (ne $vapid 3) -}}
  {{- fail "meiun-helm: vapid.subject, vapid.publicKey and vapid.privateKey must be set together, or none" -}}
{{- end -}}
{{- end -}}

{{/*
The env both the API and the worker need: the database and the minds' routes. One helper so the two never disagree.
*/}}
{{- define "meiun-helm.sharedEnv" -}}
{{- $ := . -}}
- name: NODE_ENV
  value: "production"
{{- if $.Values.postgres.enabled }}
- name: DATABASE_URL
  value: {{ printf "postgres://%s@%s-postgres:5432/%s" $.Values.postgres.user (include "meiun-helm.fullname" $) $.Values.postgres.db | quote }}
- name: PGPASSWORD
  {{- include "meiun-helm.credentialEnv" $.Values.postgres.password | nindent 2 }}
{{- else }}
- name: DATABASE_URL
  value: {{ $.Values.database.url | quote }}
{{- end }}
- name: METRICS_PORT
  value: {{ $.Values.metrics.port | quote }}
{{- range $name, $key := dict "MEIUN_LOCAL_BASE_URL" "localBaseUrl" "MEIUN_LOCAL_MODEL" "localModel" "MEIUN_HOSTED_MODEL" "hostedModel" "MEIUN_TOKENS_PER_DAY" "tokensPerDay" }}
{{- with (index $.Values.minds $key) }}
- name: {{ $name }}
  value: {{ . | quote }}
{{- end }}
{{- end }}
{{- if include "meiun-helm.isSet" $.Values.minds.localApiKey }}
- name: MEIUN_LOCAL_API_KEY
  {{- include "meiun-helm.credentialEnv" $.Values.minds.localApiKey | nindent 2 }}
{{- end }}
{{- if include "meiun-helm.isSet" $.Values.minds.anthropicApiKey }}
- name: ANTHROPIC_API_KEY
  {{- include "meiun-helm.credentialEnv" $.Values.minds.anthropicApiKey | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
The hardened container securityContext the API, the worker and the web app share.
*/}}
{{- define "meiun-helm.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
{{- end -}}
