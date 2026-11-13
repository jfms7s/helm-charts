# volley-helm

Deploys [volley](https://github.com/jfms7s/volley), a browser arena brawler for 2-10 players, as one server container. The container serves the built client over HTTP and the game WebSocket at `/ws`.

## Single replica, by design

Rooms live in the server process's memory. The chart therefore runs exactly one pod with a `Recreate` rollout: a second pod would split the players of one room code across two games. Every deploy or pod restart ends the matches in progress; players reload the room link and start again. There is no volume.

## Install

```
helm install volley charts/volley-helm \
  --set ingress.enabled=true \
  --set ingress.hosts[0].host=volley.example.com \
  --set ingress.hosts[0].paths[0].path=/
```

## Values

| Key | Default | Meaning |
| --- | --- | --- |
| `image.repository` / `image.tag` | `ghcr.io/jfms7s/volley` / `v0.1.0` | Image to run |
| `imagePullSecrets` | `[]` | Pull secrets, if the image is private |
| `server.extraEnv` | `[]` | Extra env (`VOLLEY_LAYOUT`, `VOLLEY_LAG_MS`) |
| `resources` | `{}` | Container requests and limits |
| `securityContext` | non-root uid 1000, read-only root fs | Container hardening |
| `ingress.*` | disabled | Ingress; WebSocket upgrades on `/ws` need no extra annotation on Traefik |

Probes use the server's `/healthz` endpoint.
