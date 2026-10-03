{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "budget-manager-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "api|web|worker|nats" "component" "api|frontend|worker|message-bus").
*/}}
{{- define "budget-manager-helm.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: budget-manager
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
helm.sh/chart: {{ include "budget-manager-helm.chart" .context }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from
budget-manager-helm.labels because selectors (Deployment
matchLabels / Service selector) are immutable after creation, so this must
never gain chart-version-derived keys. Pass
(dict "context" $ "name" "api|web|worker|nats").
*/}}
{{- define "budget-manager-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Render an env var's value/valueFrom body from a {value, valueFrom} map, e.g.
{{- include "budget-manager-helm.credentialEnv" .Values.database.authToken | nindent N }}
valueFrom (a standard corev1 EnvVarSource body, e.g. secretKeyRef) takes
precedence over value when both are set. value defaults to "CHANGE_ME",
since Argo CD does not support Helm's `lookup` function, so -- unlike a
plain `helm install` -- these can't be safely auto-generated and persisted
across syncs; callers must pin one explicitly.
*/}}
{{- define "budget-manager-helm.credentialEnv" -}}
{{- if .valueFrom -}}
valueFrom: {{- toYaml .valueFrom | nindent 2 }}
{{- else -}}
value: {{ .value | default "CHANGE_ME" | quote }}
{{- end -}}
{{- end -}}

{{/*
Fail the render if a required credential is not properly set.
For credentials with {value, valueFrom}: fail if both are empty/CHANGE_ME/missing.
For simple values: fail if empty/CHANGE_ME.
Pass: (dict "context" $ "credentialName" "database.authToken" "credential" .Values.database.authToken)
or:   (dict "context" $ "credentialName" "database.url" "value" .Values.database.url)
*/}}
{{- define "budget-manager-helm.requiredCredential" -}}
{{- $name := .credentialName -}}
{{- if .credential -}}
  {{- $cred := .credential -}}
  {{- if and (or (eq ($cred.value | default "") "") (eq ($cred.value | default "") "CHANGE_ME")) (not $cred.valueFrom) -}}
    {{- fail (printf "budget-manager-helm: %s must be set (value or valueFrom)" $name) -}}
  {{- end -}}
{{- else if .value -}}
  {{- if or (eq (.value | default "") "") (eq (.value | default "") "CHANGE_ME") -}}
    {{- fail (printf "budget-manager-helm: %s must be set, e.g. http://budget-manager-libsql:8080" $name) -}}
  {{- end -}}
{{- end -}}
{{- end -}}

{{/*
Validate that an origin override is a valid URL (^https?://[^/]+$).
Pass: (dict "context" $ "originName" "webOrigin" "origin" .Values.webOrigin)
*/}}
{{- define "budget-manager-helm.validateOrigin" -}}
{{- if and (.origin) (not (regexMatch "^https?://[^/]+$" .origin)) -}}
  {{- fail (printf "budget-manager-helm: %s must be a valid origin (e.g. https://example.com, got %q)" .originName .origin) -}}
{{- end -}}
{{- end -}}
