# cicd

The same delivery pipeline — lint → test → build + scan → gated deploy — expressed for three systems, so
the pattern transfers whatever a team already runs.

| Path | Platform |
|---|---|
| `gitlab/.gitlab-ci.yml` | GitLab CI: yaml/shell/terraform lint, unit tests, rootless kaniko build, Trivy scan, Terraform plan, manual-gate apply. |
| `jenkins/Jenkinsfile` | Jenkins declarative pipeline: quality gates on an agent, then an `input` approval before deploy. |
| `azure-pipelines/azure-pipelines.yml` | Azure DevOps multi-stage: validate → build + scan → deploy with an Environment approval. |

Common principles: supply-chain scanning (Trivy) blocks High/Critical; production changes are approved by
a person; secrets come from the platform's protected variables / credential store, never the repo.

The repository's own CI lives in `.github/workflows/portfolio-ci.yml` and validates every tool here.
