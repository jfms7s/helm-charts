{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "tradelab-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "tradelab" "component" "app|storage|backup").
*/}}
{{- define "tradelab-helm.labels" -}}
{{ include "tradelab-helm.podLabels" . }}
helm.sh/chart: {{ include "tradelab-helm.chart" .context }}
{{- end -}}

{{/*
Pod-template labels: the standard labels minus helm.sh/chart, so a chart
release that does not change a workload's spec does not restart its pods.
Same arguments as tradelab-helm.labels.
*/}}
{{- define "tradelab-helm.podLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: tradelab
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from tradelab-helm.labels because
selectors (Deployment matchLabels / Service selector) are immutable after
creation, so this must never gain chart-version-derived keys. The backup Job's
pod affinity selects the app pod by these. Pass (dict "context" $ "name" "tradelab").
*/}}
{{- define "tradelab-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
The pod security context, with seLinuxOptions.level from seLinuxLevel when set.
The app pod and the backup Job use the same one, so the Job never relabels the
shared data volume.
*/}}
{{- define "tradelab-helm.podSecurityContext" -}}
{{- $psc := deepCopy (.Values.podSecurityContext | default dict) }}
{{- if .Values.seLinuxLevel }}
{{- $se := deepCopy ($psc.seLinuxOptions | default dict) }}
{{- $_ := set $se "level" .Values.seLinuxLevel }}
{{- $_ := set $psc "seLinuxOptions" $se }}
{{- end }}
{{- toYaml $psc }}
{{- end -}}

{{/*
The data volume (`name: data`); fails without persistence.volume.
*/}}
{{- define "tradelab-helm.dataVolume" -}}
- name: data
  {{- if .Values.persistence.volume }}
  {{- toYaml .Values.persistence.volume | nindent 2 }}
  {{- else }}
  {{- fail "tradelab-helm: set persistence.volume (or persistence.claim.size and point volume at <release>-tradelab-data)" }}
  {{- end }}
{{- end -}}

{{/*
The /data mount, with the subPath when set.
*/}}
{{- define "tradelab-helm.dataMount" -}}
- name: data
  mountPath: /data
  {{- with .Values.persistence.subPath }}
  subPath: {{ . }}
  {{- end }}
{{- end -}}

{{/*
The Alpaca keys from alpaca.existingSecret, for the worker and live only.
Include it only when alpaca.existingSecret is set.
*/}}
{{- define "tradelab-helm.alpacaEnv" -}}
{{- with .Values.alpaca.existingSecret -}}
- name: APCA_API_KEY_ID
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: APCA_API_KEY_ID
- name: APCA_API_SECRET_KEY
  valueFrom:
    secretKeyRef:
      name: {{ . }}
      key: APCA_API_SECRET_KEY
{{- end }}
{{- end -}}
