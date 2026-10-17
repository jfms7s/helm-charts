{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "eng-metrics-lab-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels. Pass (dict "context" $ "name" "postgres|migrate|collector|backup" "component" "...").
*/}}
{{- define "eng-metrics-lab-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: eng-metrics-lab
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "eng-metrics-lab-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels: immutable after creation, so never chart-version-derived. Pass (dict "context" $ "name" "...").
*/}}
{{- define "eng-metrics-lab-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
The Postgres Service's name, which is also its in-cluster host.
*/}}
{{- define "eng-metrics-lab-helm.postgresHost" -}}
{{ .Release.Name }}-postgres
{{- end -}}

{{/*
An env var read from the existing Secret. Pass (dict "context" $ "name" "KEY" "optional" bool).
*/}}
{{- define "eng-metrics-lab-helm.secretEnv" -}}
- name: {{ .name }}
  valueFrom:
    secretKeyRef:
      name: {{ .context.Values.existingSecret }}
      key: {{ .name }}
      {{- if .optional }}
      optional: true
      {{- end }}
{{- end -}}

{{/*
Hardening for the quality-collector image, which has no USER: uid 1000, read-only root, writable /tmp (HOME).
*/}}
{{- define "eng-metrics-lab-helm.collectorSecurityContext" -}}
runAsUser: 1000
runAsNonRoot: true
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
{{- end -}}

{{/*
The pod-level settings shared by the migrate and collector pods.
*/}}
{{- define "eng-metrics-lab-helm.collectorPodSpec" -}}
automountServiceAccountToken: false
securityContext:
  seccompProfile:
    type: RuntimeDefault
{{- with .Values.imagePullSecrets }}
imagePullSecrets:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end -}}
