# meiun-helm

Deploys [meiun](https://github.com/jfms7s/meiun), a village sim whose villagers are LLM-driven, as four parts behind one host:

| Part | Image | Notes |
|---|---|---|
| `api` | `ghcr.io/jfms7s/meiun-api` | Better Auth, tRPC, SSE on 3000; runs the database migrations on start; metrics on 9464 |
| `worker` | `ghcr.io/jfms7s/meiun-worker` | the village scheduler, the minds' job queue, Web Push; one replica, Recreate; metrics on 9464 |
| `web` | `ghcr.io/jfms7s/meiun-web` | the PWA, static files on nginx-unprivileged (8080) |
| `postgres` | `docker.io/pgvector/pgvector` (pg18) | optional (`postgres.enabled`); one replica, Recreate, on a persistent volume |

The Ingress serves one host: `/trpc` and `/api` go to the API, everything else to the PWA. The app sets no CORS headers, so the two must share the origin. The metrics port is never routed; enable `metrics.serviceMonitor` for Prometheus.

## Required values

- `host`: the bare public hostname. `BETTER_AUTH_URL` and `WEB_ORIGIN` are `https://<host>`.
- `betterAuthSecret`: at least 32 characters.
- With the in-chart Postgres: `postgres.password` and a persistent `postgres.persistence.volume` (the chart can create the claim with `postgres.persistence.claim`). Otherwise `database.url`.

Credentials are `{value, valueFrom}` maps; `valueFrom` (for example a `secretKeyRef`) wins. The chart never generates a secret, and the render fails while a required one is unset or `CHANGE_ME`.

## Optional values

- `oidc`: login through an OpenID Connect provider, on when `issuer`, `clientId` and `clientSecret` are all set. Register `https://<host>/api/auth/callback/<providerId>` (default `homelab`) as the redirect URI.
- `vapid`: Web Push, on when `subject`, `publicKey` and `privateKey` are all set. The private key reaches the worker only.
- `minds`: the model routes (`MEIUN_*`) and `anthropicApiKey`, given to the API and the worker.

`ci/test-values.yaml` has valid dummy values for linting and the unit tests.
