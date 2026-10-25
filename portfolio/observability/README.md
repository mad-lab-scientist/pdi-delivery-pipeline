# observability

Monitoring configuration validated in CI with `promtool`.

| Path | What it is |
|---|---|
| `prometheus/prometheus.yml` | Scrape config (node, cAdvisor, blackbox) with file-based service discovery and relabeling. |
| `prometheus/rules/` | Alert rules: node availability/resources/disk-prediction, endpoint probes and TLS-expiry alerts. |
| `prometheus/targets/` | File-SD target lists (edit to add hosts/endpoints; Prometheus reloads them live). |
| `alertmanager/alertmanager.yml` | Routing by severity to PagerDuty / Slack / email, with inhibition and secrets from files. |
| `grafana/provisioning/` | Datasource (Prometheus, Loki) and dashboard provisioning. |

Deploy with [`../containers/docker-compose/monitoring/`](../containers/docker-compose/monitoring/).
The `node_exporter` agent is installed by the Ansible role of the same name.
