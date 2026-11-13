{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "volley-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels. Pass (dict "context" $ "name" "server" "component" "server").
*/}}
{{- define "volley-helm.labels" -}}
{{ include "volley-helm.podLabels" . }}
helm.sh/chart: {{ include "volley-helm.chart" .context }}
{{- end -}}

{{/*
Pod-template labels: the standard labels minus helm.sh/chart, so a chart
release that does not change the spec does not restart pods (and drop every
live match). Same arguments as volley-helm.labels.
*/}}
{{- define "volley-helm.podLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: volley
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
{{- end -}}

{{/*
Selector labels. Immutable after creation, so never add chart-version keys.
Pass (dict "context" $ "name" "server").
*/}}
{{- define "volley-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}
