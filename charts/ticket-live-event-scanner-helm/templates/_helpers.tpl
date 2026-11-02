{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "ticket-live-event-scanner-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "nats|scraper|telegram-notifier|web-ui-api|web-ui-frontend" "component" "message-bus|scraper|notifier|api|frontend").
*/}}
{{- define "ticket-live-event-scanner-helm.labels" -}}
{{ include "ticket-live-event-scanner-helm.podLabels" . }}
helm.sh/chart: {{ include "ticket-live-event-scanner-helm.chart" .context }}
{{- end -}}

{{/*
Pod-template labels: the standard labels minus helm.sh/chart, so a chart
release that does not change a workload's spec does not restart its pods.
Same arguments as ticket-live-event-scanner-helm.labels.
*/}}
{{- define "ticket-live-event-scanner-helm.podLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: ticket-scanner
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from
ticket-live-event-scanner-helm.labels because selectors (Deployment
matchLabels / Service selector) are immutable after creation, so this must
never gain chart-version-derived keys. Pass
(dict "context" $ "name" "nats|scraper|telegram-notifier|web-ui-api|web-ui-frontend").
*/}}
{{- define "ticket-live-event-scanner-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Render an env var's value/valueFrom body from a {value, valueFrom} map, e.g.
{{- include "ticket-live-event-scanner-helm.credentialEnv" .Values.turso.authToken | nindent N }}
valueFrom (a standard corev1 EnvVarSource body, e.g. secretKeyRef) takes
precedence over value when both are set. value defaults to "CHANGE_ME",
since Argo CD does not support Helm's `lookup` function, so -- unlike a
plain `helm install` -- these can't be safely auto-generated and persisted
across syncs; callers must pin one explicitly.
*/}}
{{- define "ticket-live-event-scanner-helm.credentialEnv" -}}
{{- if .valueFrom -}}
valueFrom: {{- toYaml .valueFrom | nindent 2 }}
{{- else -}}
value: {{ .value | default "CHANGE_ME" | quote }}
{{- end -}}
{{- end -}}

{{/*
CORS_ORIGIN for web-ui-api: webUiApi.corsOrigin when set; else, with the
ingress on, https://<first ingress host> (the origin the frontend is served
from); else "*" (the API is then reachable only in-cluster).
*/}}
{{- define "ticket-live-event-scanner-helm.corsOrigin" -}}
{{- if .Values.webUiApi.corsOrigin -}}
{{- .Values.webUiApi.corsOrigin -}}
{{- else if and .Values.ingress.enabled .Values.ingress.hosts (first .Values.ingress.hosts).host -}}
{{- printf "https://%s" (first .Values.ingress.hosts).host -}}
{{- else -}}
*
{{- end -}}
{{- end -}}

{{/*
Render-time guard for one credential in the {value, valueFrom} shape: fails
unless valueFrom is set or value is non-empty and not the CHANGE_ME
placeholder. A null or missing key counts as unset (this repo is public, so a
placeholder secret is a known secret). Pass
(dict "credentialName" "server.jwtSecret" "credential" .Values.server.jwtSecret).
*/}}
{{- define "ticket-live-event-scanner-helm.requiredCredential" -}}
{{- $cred := .credential | default dict -}}
{{- $value := trim (toString ($cred.value | default "")) -}}
{{- if and (or (eq $value "") (eq $value "CHANGE_ME")) (not $cred.valueFrom) -}}
  {{- fail (printf "ticket-live-event-scanner-helm: %s must be set (value or valueFrom); the CHANGE_ME placeholder is not accepted" .credentialName) -}}
{{- end -}}
{{- end -}}

{{/*
Same guard for a plain scalar value. Pass (dict "name" "smtp.from" "value" .Values.smtp.from).
*/}}
{{- define "ticket-live-event-scanner-helm.requiredScalar" -}}
{{- $value := trim (toString (.value | default "")) -}}
{{- if or (eq $value "") (eq $value "CHANGE_ME") -}}
  {{- fail (printf "ticket-live-event-scanner-helm: %s must be set; the CHANGE_ME placeholder is not accepted" .name) -}}
{{- end -}}
{{- end -}}

{{/*
Every required credential, checked at the top of each template that consumes
one, so no template renders on its own with a placeholder. Renders nothing.
*/}}
{{- define "ticket-live-event-scanner-helm.validate" -}}
{{- $ := . -}}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "turso.databaseUrl" "credential" $.Values.turso.databaseUrl) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "turso.authToken" "credential" $.Values.turso.authToken) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "telegram.botToken" "credential" $.Values.telegram.botToken) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "telegram.chatId" "credential" $.Values.telegram.chatId) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "smtp.username" "credential" $.Values.smtp.username) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "smtp.password" "credential" $.Values.smtp.password) }}
{{- include "ticket-live-event-scanner-helm.requiredScalar" (dict "name" "smtp.from" "value" $.Values.smtp.from) }}
{{- include "ticket-live-event-scanner-helm.requiredScalar" (dict "name" "smtp.to" "value" $.Values.smtp.to) }}
{{- end -}}
