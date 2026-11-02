{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "data-lab-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass
(dict "context" $ "name" "spark|flink" "component" "namespace|rbac").
*/}}
{{- define "data-lab-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: data-lab
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "data-lab-helm.chart" .context }}
{{- end -}}
