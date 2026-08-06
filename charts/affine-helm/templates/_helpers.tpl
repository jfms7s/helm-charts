{{/*
Resolve the Postgres password: reuse the value already stored in the release's
Secret (so upgrades don't rotate it), otherwise fall back to the user-supplied
value, otherwise generate a random one.
*/}}
{{- define "affine.postgres.password" -}}
{{- $secret := lookup "v1" "Secret" .Release.Namespace (printf "%s-affine-postgres" .Release.Name) -}}
{{- if $secret -}}
{{- index $secret.data "postgres-password" | b64dec -}}
{{- else if .Values.postgres.password -}}
{{- .Values.postgres.password -}}
{{- else -}}
{{- randAlphaNum 24 -}}
{{- end -}}
{{- end -}}
