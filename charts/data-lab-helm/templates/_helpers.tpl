{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "data-lab-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Base name for resources — the release name, overridable via fullnameOverride
(or partially via nameOverride).
*/}}
{{- define "data-lab-helm.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else if .Values.nameOverride -}}
{{- printf "%s-%s" .Release.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{/*
Standard labels for a component. Pass
(dict "context" $ "name" "minio|spark|flink|seed" "component" "object-store|rbac|seeder").
*/}}
{{- define "data-lab-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: data-lab
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "data-lab-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels — never gains chart-version-derived keys (selectors are immutable).
Pass (dict "context" $ "name" "minio").
*/}}
{{- define "data-lab-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}
