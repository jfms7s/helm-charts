{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "padel-score-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "server" "component" "server|storage").
*/}}
{{- define "padel-score-helm.labels" -}}
{{ include "padel-score-helm.podLabels" . }}
helm.sh/chart: {{ include "padel-score-helm.chart" .context }}
{{- end -}}

{{/*
Pod-template labels: the standard labels minus helm.sh/chart, so a chart
release that does not change a workload's spec does not restart its pods.
Same arguments as padel-score-helm.labels.
*/}}
{{- define "padel-score-helm.podLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: padel-score
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from padel-score-helm.labels because
selectors (Deployment matchLabels / Service selector) are immutable after
creation, so this must never gain chart-version-derived keys. Pass
(dict "context" $ "name" "server").
*/}}
{{- define "padel-score-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}
