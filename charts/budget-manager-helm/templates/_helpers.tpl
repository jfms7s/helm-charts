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

{{/*
Every chart-wide render-time guard, in one place. Both the api and the worker
template include it, so neither can ever render on its own with a placeholder
credential, a missing database, an unshared attachments volume or a bad origin.
*/}}
{{- define "budget-manager-helm.validate" -}}
{{- $ := . -}}
{{- if and (eq $.Values.database.url "") (not $.Values.sqld.enabled) -}}
  {{- fail "budget-manager-helm: database.url must be set (or enable sqld.enabled)" -}}
{{- end -}}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "database.authToken" "credential" $.Values.database.authToken) }}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "sessionCookieSecret" "credential" $.Values.sessionCookieSecret) }}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "appEncryptionKey" "credential" $.Values.appEncryptionKey) }}
{{- include "budget-manager-helm.validateOrigin" (dict "context" $ "originName" "webOrigin" "origin" $.Values.webOrigin) }}
{{- if or ($.Values.smtp.url.value) ($.Values.smtp.url.valueFrom) -}}
  {{- if and (or (eq ($.Values.smtp.from.value | default "") "") (eq ($.Values.smtp.from.value | default "") "CHANGE_ME")) (not $.Values.smtp.from.valueFrom) -}}
    {{- fail "budget-manager-helm: smtp.from must be set when smtp.url is configured" -}}
  {{- end -}}
{{- end -}}
{{- if not $.Values.attachments.volume -}}
  {{- fail "budget-manager-helm: attachments.volume must be a volume shared by the api and the worker (e.g. nfs: or a ReadWriteMany persistentVolumeClaim)" -}}
{{- end -}}
{{- end -}}

{{/*
The database URL the api AND the worker connect to: an explicit database.url,
else the in-chart sqld. One helper so the two can never disagree (the worker
once rendered an empty URL while the api derived the sqld one).
*/}}
{{- define "budget-manager-helm.databaseUrl" -}}
{{- if .Values.database.url -}}
{{- .Values.database.url -}}
{{- else if .Values.sqld.enabled -}}
http://{{ .Release.Name }}-budget-manager-sqld:8080
{{- end -}}
{{- end -}}

{{/*
bank-sync's render-time guards (bankSync.enabled only): every value it can't
start without, checked here so a misconfigured release fails at render rather
than as a crash-looping pod.
*/}}
{{- define "budget-manager-helm.bankSyncValidate" -}}
{{- $ := . -}}
{{- $bs := $.Values.bankSync -}}
{{- if not $bs.host -}}
  {{- fail "budget-manager-helm: bankSync.host must be set (the admin page's ingress host; BANK_SYNC_PUBLIC_URL is https://<host>)" -}}
{{- end -}}
{{- if not (regexMatch "^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$" $bs.host) -}}
  {{- fail (printf "budget-manager-helm: bankSync.host must be a bare lower-case hostname, no scheme, port or path (got %q)" $bs.host) -}}
{{- end -}}
{{- if or (not $bs.persistence.volume) (hasKey $bs.persistence.volume "emptyDir") -}}
  {{- fail "budget-manager-helm: bankSync.persistence.volume must be persistent storage, not emptyDir (its SQLite database lives there)" -}}
{{- end -}}
{{- if or (not $bs.privateKeySecret.name) (not $bs.privateKeySecret.key) -}}
  {{- fail "budget-manager-helm: bankSync.privateKeySecret.name and .key must be set (the Secret holding the Enable Banking private key)" -}}
{{- end -}}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "bankSync.ebAppId" "credential" $bs.ebAppId) }}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "bankSync.bmToken" "credential" $bs.bmToken) }}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "bankSync.adminPasswordHash" "credential" $bs.adminPasswordHash) }}
{{- include "budget-manager-helm.requiredCredential" (dict "context" $ "credentialName" "bankSync.sessionSecret" "credential" $bs.sessionSecret) }}
{{- if and (not $bs.sessionSecret.valueFrom) (lt (len ($bs.sessionSecret.value | default "")) 32) -}}
  {{- fail "budget-manager-helm: bankSync.sessionSecret must be at least 32 characters" -}}
{{- end -}}
{{- $interval := int $bs.intervalHours -}}
{{- if or (lt $interval 6) (gt $interval 168) -}}
  {{- fail (printf "budget-manager-helm: bankSync.intervalHours must be 6-168 (got %v)" $bs.intervalHours) -}}
{{- end -}}
{{- $trust := toString ($bs.trustProxy | default "") -}}
{{- if $trust -}}
  {{- /* Each entry an IPv4/IPv6 address, optionally with a /prefix in range (0-32 or 0-128), as bank-sync's own parser requires. */ -}}
  {{- $ipv4 := "^((25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])\\.){3}(25[0-5]|2[0-4][0-9]|1[0-9][0-9]|[1-9]?[0-9])$" -}}
  {{- $ipv6 := "^[0-9A-Fa-f]*:[0-9A-Fa-f:.]*$" -}}
  {{- range $entry := splitList "," $trust -}}
    {{- $parts := splitList "/" (trim $entry) -}}
    {{- $addr := first $parts -}}
    {{- $max := -1 -}}
    {{- if regexMatch $ipv4 $addr }}{{ $max = 32 }}{{ else if regexMatch $ipv6 $addr }}{{ $max = 128 }}{{ end -}}
    {{- $ok := and (ge $max 0) (le (len $parts) 2) -}}
    {{- if and $ok (eq (len $parts) 2) -}}
      {{- $prefix := last $parts -}}
      {{- $ok = and (regexMatch "^[0-9]{1,3}$" $prefix) (le (atoi $prefix) $max) -}}
    {{- end -}}
    {{- if not $ok -}}
      {{- fail (printf "budget-manager-helm: bankSync.trustProxy must be a comma-separated list of IP addresses or CIDR ranges, never \"true\" or a hop count (got %q)" $trust) -}}
    {{- end -}}
  {{- end -}}
{{- end -}}
{{- end -}}
