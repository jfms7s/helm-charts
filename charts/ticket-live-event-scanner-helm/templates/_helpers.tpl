{{/*
Chart name and version, for the helm.sh/chart label.
*/}}
{{- define "ticket-live-event-scanner-helm.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Standard labels for a component. Pass (dict "context" $ "name" "nats|web-ui-api" "component" "message-bus|api|storage").
*/}}
{{- define "ticket-live-event-scanner-helm.labels" -}}
{{ include "ticket-live-event-scanner-helm.podLabels" . }}
helm.sh/chart: {{ include "ticket-live-event-scanner-helm.chart" .context }}
{{- end -}}

{{/*
Pod-template labels: the standard labels minus helm.sh/chart, so a chart
release that does not change a workload's spec does not restart its pods.
Same arguments as ticket-live-event-scanner-helm.labels.
*/}}
{{- define "ticket-live-event-scanner-helm.podLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
app.kubernetes.io/component: {{ .component }}
app.kubernetes.io/part-of: ticket-scanner
app.kubernetes.io/managed-by: {{ .context.Release.Service }}
{{- end -}}

{{/*
Selector labels for a component. Kept separate from
ticket-live-event-scanner-helm.labels because selectors (Deployment
matchLabels / Service selector) are immutable after creation, so this must
never gain chart-version-derived keys. Pass
(dict "context" $ "name" "nats|web-ui-api").
*/}}
{{- define "ticket-live-event-scanner-helm.selectorLabels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .context.Release.Name }}
{{- end -}}

{{/*
Every credential the chart consumes, as Secret key -> its {value, valueFrom}
map. Fills the dict passed as .out; pass (dict "ctx" $ "out" (dict)).
*/}}
{{- define "ticket-live-event-scanner-helm.credentials" -}}
{{- $v := .ctx.Values -}}
{{- if include "ticket-live-event-scanner-helm.sqldInUse" .ctx -}}
{{- $_ := set .out "TURSO_DATABASE_URL" ($v.turso.databaseUrl | default dict) -}}
{{- $_ := set .out "TURSO_AUTH_TOKEN" ($v.turso.authToken | default dict) -}}
{{- end -}}
{{- $_ := set .out "TELEGRAM_BOT_TOKEN" ($v.telegram.botToken | default dict) -}}
{{- $_ := set .out "TELEGRAM_CHAT_ID" ($v.telegram.chatId | default dict) -}}
{{- $_ := set .out "SMTP_USERNAME" ($v.smtp.username | default dict) -}}
{{- $_ := set .out "SMTP_PASSWORD" ($v.smtp.password | default dict) -}}
{{- if include "ticket-live-event-scanner-helm.natsAuthEnabled" .ctx -}}
{{- $_ := set .out "NATS_TOKEN" $v.nats.auth.token -}}
{{- end -}}
{{- end -}}

{{/*
"true" when the libSQL server (turso.*) is in use: the database is the
server itself, or a SQLite file that is still filled from it (see
database.sqlite.importFromSqld). Empty for SQLite alone.
*/}}
{{- define "ticket-live-event-scanner-helm.sqldInUse" -}}
{{- $s := (.Values.database).sqlite | default dict -}}
{{- if or (not $s.enabled) (ne (toString (hasKey $s "importFromSqld" | ternary $s.importFromSqld true)) "false") -}}
true
{{- end -}}
{{- end -}}

{{/*
Name of the PVC holding web-ui-api's SQLite file: database.sqlite.existingClaim
or the chart-created claim.
*/}}
{{- define "ticket-live-event-scanner-helm.sqliteClaimName" -}}
{{- $s := .Values.database.sqlite -}}
{{- default (printf "%s-ticket-scanner-web-ui-api-data" .Release.Name) $s.existingClaim -}}
{{- end -}}

{{/*
"true" when nats.auth.token is set (valueFrom, or any non-empty value), else
empty. Off means no NATS auth anywhere: the render matches a chart without
the option. A whitespace-only value counts as set, so the guard in validate
rejects it instead of silently leaving auth off.
*/}}
{{- define "ticket-live-event-scanner-helm.natsAuthEnabled" -}}
{{- $tok := ((.Values.nats).auth).token | default dict -}}
{{- if or $tok.valueFrom (ne (toString ($tok.value | default "")) "") -}}
true
{{- end -}}
{{- end -}}

{{/*
Name of the ConfigMap holding the NATS server config (auth on only).
*/}}
{{- define "ticket-live-event-scanner-helm.natsConfigName" -}}
{{- printf "%s-ticket-scanner-nats-config" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
NATS client env for a workload: NATS_URL, plus NATS_TOKEN when
nats.auth.token is set. Pass the root context.
*/}}
{{- define "ticket-live-event-scanner-helm.natsClientEnv" -}}
- name: NATS_URL
  value: nats://{{ .Release.Name }}-ticket-scanner-nats:4222
{{- if include "ticket-live-event-scanner-helm.natsAuthEnabled" . }}
- name: NATS_TOKEN
  {{- include "ticket-live-event-scanner-helm.credentialEnv" (dict "ctx" . "key" "NATS_TOKEN") | nindent 2 }}
{{- end }}
{{- end -}}

{{/*
Name of the chart-owned Secret that holds every credential given as value.
*/}}
{{- define "ticket-live-event-scanner-helm.credentialsSecretName" -}}
{{- printf "%s-ticket-scanner-credentials" .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
One credential value as the string the app receives. YAML numbers arrive as
float64, so an integral one (a Telegram chat ID, say) is printed as an
integer instead of in exponent form.
*/}}
{{- define "ticket-live-event-scanner-helm.credentialString" -}}
{{- $v := . | default "CHANGE_ME" -}}
{{- if and (kindIs "float64" $v) (eq $v (float64 (int64 $v))) -}}
{{- printf "%d" (int64 $v) -}}
{{- else -}}
{{- toString $v -}}
{{- end -}}
{{- end -}}

{{/*
Secret data: one base64 key per credential given as value (no valueFrom),
sorted. Pass (dict "ctx" $) for every credential, or add "keys" (a list of
Secret keys) for just those. Renders nothing when none of them uses value.
*/}}
{{- define "ticket-live-event-scanner-helm.credentialsSecretData" -}}
{{- $creds := dict -}}
{{- include "ticket-live-event-scanner-helm.credentials" (dict "ctx" .ctx "out" $creds) -}}
{{- $only := .keys | default (keys $creds) -}}
{{- range $key := keys $creds | sortAlpha -}}
{{- $cred := get $creds $key -}}
{{- if and (has $key $only) (not $cred.valueFrom) }}
{{ $key }}: {{ include "ticket-live-event-scanner-helm.credentialString" $cred.value | b64enc | quote }}
{{- end -}}
{{- end -}}
{{- end -}}

{{/*
Pod-template annotation that rolls a workload when one of the credentials it
reads changes while given as value (its env var points at the chart Secret,
so the pod spec itself would not change). Pass (dict "ctx" $ "keys" (list
...)) with the Secret keys the workload reads. Renders nothing when none of
them uses value. The hash is unsalted: like any hash of a secret it can be
brute-forced offline, so give value credentials high entropy (or use
valueFrom).
*/}}
{{- define "ticket-live-event-scanner-helm.credentialsChecksum" -}}
{{- with include "ticket-live-event-scanner-helm.credentialsSecretData" . -}}
annotations:
  checksum/credentials: {{ sha256sum . }}
{{- end -}}
{{- end -}}

{{/*
Render an env var's valueFrom body for one credential, by its Secret key, e.g.
{{- include "ticket-live-event-scanner-helm.credentialEnv" (dict "ctx" $ "key" "TURSO_DATABASE_URL") | nindent N }}
A credential's own valueFrom (a standard corev1 EnvVarSource body, e.g.
secretKeyRef) is passed through; a credential given as value is read from the
chart Secret, so it never appears in a workload spec. Never emits both value
and valueFrom on one EnvVar. Credentials are never generated: Argo CD has no
`lookup`, so a generated value would rotate on every sync.
*/}}
{{- define "ticket-live-event-scanner-helm.credentialEnv" -}}
{{- $creds := dict -}}
{{- include "ticket-live-event-scanner-helm.credentials" (dict "ctx" .ctx "out" $creds) -}}
{{- if not (hasKey $creds .key) -}}
{{- fail (printf "ticket-live-event-scanner-helm: unknown credential key %s" .key) -}}
{{- end -}}
{{- $cred := get $creds .key -}}
{{- if $cred.valueFrom -}}
valueFrom: {{- toYaml $cred.valueFrom | nindent 2 }}
{{- else -}}
valueFrom:
  secretKeyRef:
    name: {{ include "ticket-live-event-scanner-helm.credentialsSecretName" .ctx }}
    key: {{ .key }}
{{- end -}}
{{- end -}}

{{/*
Render-time guard for one credential in the {value, valueFrom} shape: fails
unless valueFrom is set or value is non-empty and not the CHANGE_ME
placeholder. A null or missing key counts as unset (this repo is public, so a
placeholder secret is a known secret). Pass
(dict "credentialName" "server.jwtSecret" "credential" .Values.server.jwtSecret).
*/}}
{{- define "ticket-live-event-scanner-helm.requiredCredential" -}}
{{- $cred := .credential | default dict -}}
{{- $value := trim (toString ($cred.value | default "")) -}}
{{- if and (or (eq $value "") (eq $value "CHANGE_ME")) (not $cred.valueFrom) -}}
  {{- fail (printf "ticket-live-event-scanner-helm: %s must be set (value or valueFrom); the CHANGE_ME placeholder is not accepted" .credentialName) -}}
{{- end -}}
{{- end -}}

{{/*
Same guard for a plain scalar value. Pass (dict "name" "smtp.from" "value" .Values.smtp.from).
*/}}
{{- define "ticket-live-event-scanner-helm.requiredScalar" -}}
{{- $value := trim (toString (.value | default "")) -}}
{{- if or (eq $value "") (eq $value "CHANGE_ME") -}}
  {{- fail (printf "ticket-live-event-scanner-helm: %s must be set; the CHANGE_ME placeholder is not accepted" .name) -}}
{{- end -}}
{{- end -}}

{{/*
Every required credential, checked at the top of each template that consumes
one, so no template renders on its own with a placeholder. Renders nothing.
*/}}
{{- define "ticket-live-event-scanner-helm.validate" -}}
{{- $ := . -}}
{{- if include "ticket-live-event-scanner-helm.sqldInUse" $ }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "turso.databaseUrl" "credential" $.Values.turso.databaseUrl) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "turso.authToken" "credential" $.Values.turso.authToken) }}
{{- end }}
{{- if $.Values.database.sqlite.enabled }}
{{- if and (not $.Values.database.sqlite.existingClaim) (not $.Values.database.sqlite.claim.storageClassName) }}
{{- fail "ticket-live-event-scanner-helm: database.sqlite.enabled needs a volume: set database.sqlite.claim.storageClassName and .size (the chart creates the PVC) or database.sqlite.existingClaim" }}
{{- end }}
{{- if and (not $.Values.database.sqlite.existingClaim) (not $.Values.database.sqlite.claim.size) }}
{{- fail "ticket-live-event-scanner-helm: database.sqlite.claim.size is required with database.sqlite.claim.storageClassName" }}
{{- end }}
{{- end }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "telegram.botToken" "credential" $.Values.telegram.botToken) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "telegram.chatId" "credential" $.Values.telegram.chatId) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "smtp.username" "credential" $.Values.smtp.username) }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "smtp.password" "credential" $.Values.smtp.password) }}
{{- include "ticket-live-event-scanner-helm.requiredScalar" (dict "name" "smtp.from" "value" $.Values.smtp.from) }}
{{- include "ticket-live-event-scanner-helm.requiredScalar" (dict "name" "smtp.to" "value" $.Values.smtp.to) }}
{{- if include "ticket-live-event-scanner-helm.natsAuthEnabled" $ }}
{{- include "ticket-live-event-scanner-helm.requiredCredential" (dict "credentialName" "nats.auth.token" "credential" $.Values.nats.auth.token) }}
{{- $tok := toString ($.Values.nats.auth.token.value | default "") }}
{{- if and (not $.Values.nats.auth.token.valueFrom) (or (contains "\"" $tok) (contains "\\" $tok) (contains "\n" $tok)) }}
{{- fail "ticket-live-event-scanner-helm: nats.auth.token must not contain a double quote, a backslash or a newline" }}
{{- end }}
{{- end }}
{{- end -}}

{{/*
Pod securityContext shared by every workload: non-root uid/gid 1000 (the
images' user), fsGroup so mounted volumes are group-writable, and the
runtime's default seccomp profile.
*/}}
{{- define "ticket-live-event-scanner-helm.podSecurityContext" -}}
runAsNonRoot: true
runAsUser: 1000
runAsGroup: 1000
fsGroup: 1000
seccompProfile:
  type: RuntimeDefault
{{- end -}}

{{/*
Container securityContext shared by every container: read-only root
filesystem (each container gets a /tmp emptyDir for the health file and
temp files), no privilege escalation, no capabilities.
*/}}
{{- define "ticket-live-event-scanner-helm.containerSecurityContext" -}}
allowPrivilegeEscalation: false
readOnlyRootFilesystem: true
capabilities:
  drop:
    - ALL
{{- end -}}
