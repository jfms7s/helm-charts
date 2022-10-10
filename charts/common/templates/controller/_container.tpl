{{- /* The main container included in the controller */ -}}
{{- define "common.controller.container" -}}
- name: {{ include "common.names.fullname" . }}
  image: {{ printf "%s:%s" .Values.controller.image.repository (default .Chart.AppVersion .Values.controller.image.tag) | quote }}
  imagePullPolicy: {{ .Values.controller.image.pullPolicy }}
{{- with .Values.controller.image.command }}
  command:
  {{- if kindIs "string" . }}
    - {{ . }}
  {{- else }}
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- with .Values.controller.image.args }}
  args:
  {{- if kindIs "string" . }}
    - {{ . }}
  {{- else }}
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
{{- with .Values.controller.image.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- with .Values.controller.image.lifecycle }}
  lifecycle:
    {{- toYaml . | nindent 4 }}
{{- end -}}
{{- with .Values.controller.image.termination.messagePath }}
  terminationMessagePath: {{ . }}
{{- end }}
{{- with .Values.controller.image.termination.messagePolicy }}
  terminationMessagePolicy: {{ . }}
{{- end }}
{{- with .Values.controller.image.env }}
  env:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- with .Values.controller.image.env }}
  envFrom:
    {{- toYaml . | nindent 4 }}
{{- end }}
{{- with .Values.controller.image.containerPorts }}
  ports:
  {{- range $k, $v := . }}
    {{- if kindIs "map" $v }}
    - containerPort: {{ $v.port }}
      protocol: {{ $v.protocol }}
    {{- else }}
    - containerPort: {{ $v }}
      protocol: TCP
    {{- end }}
  {{- end }}
{{- end }}
{{- with .Values.controller.image.resources }}
  resources:
  {{- toYaml . | nindent 4 }}
{{- end }}

{{- with .Values.controller.image.volumeMounts }}
  volumeMounts:
  {{- nindent 4 . }}
{{- end }}

{{- /* include "common.controller.probes" . | trim | nindent 2 */ -}}

{{- end }}