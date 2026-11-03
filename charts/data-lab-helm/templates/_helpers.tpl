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

{{/*
Pod Security Admission labels for a lab Namespace, from .Values.podSecurity:
one pod-security.kubernetes.io/<mode> (+ <mode>-version: latest) per mode
that is set; an empty mode is skipped.
*/}}
{{- define "data-lab-helm.podSecurityLabels" -}}
{{- $ps := .Values.podSecurity | default dict -}}
{{- range $mode := list "enforce" "warn" "audit" }}
{{- with get $ps $mode }}
{{- if not (has . (list "privileged" "baseline" "restricted")) }}
{{- fail (printf "data-lab-helm: podSecurity.%s must be privileged, baseline or restricted (got %q)" $mode .) }}
{{- end }}
pod-security.kubernetes.io/{{ $mode }}: {{ . }}
pod-security.kubernetes.io/{{ $mode }}-version: latest
{{- end }}
{{- end }}
{{- end -}}
