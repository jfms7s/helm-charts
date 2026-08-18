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
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: ticket-scanner
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "ticket-live-event-scanner-helm.chart" .context }}
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
