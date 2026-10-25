# containers

Container and orchestration configuration. Validated in CI with `hadolint`, `kustomize` + `kubeconform`,
and `helm lint`/`template`.

| Path | What it is |
|---|---|
| `dockerfiles/node-app.Dockerfile` | Hardened multi-stage Node build: deterministic deps, non-root runtime, minimal final image, `tini` as PID 1, healthcheck. |
| `docker-compose/monitoring/` | Self-hosted monitoring stack (Prometheus, Alertmanager, Grafana, node/blackbox/cadvisor exporters) with pinned images, log rotation and secrets from files. |
| `kubernetes/web-app/` | Production-grade manifests: Deployment (non-root, read-only rootfs, probes, topology spread), Service, Ingress (cert-manager), ConfigMap, HPA, PodDisruptionBudget, NetworkPolicy (default-deny) + a Kustomization. |
| `helm/web-service/` | Equivalent Helm chart with the same hardened defaults, templated and lint-clean. |

See [`../observability/`](../observability/) for the Prometheus/Grafana configuration these consume, and
[`../nginx/`](../nginx/) for the reverse-proxy config.
