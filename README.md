# Dhaba Orders — Team firewall-force

A seven-service restaurant ordering app, shipped to Kubernetes with a full
CI/CD pipeline, persistent storage, and shell-based monitoring.

## Team
| Member | GitHub | Slack | Primary ownership |
|---|---|---|---|
| Furqan | TODO | TODO | web, CI static analysis, check-services.sh |
| Teammate 2 | TODO | TODO | menu-api, orders-api, ECR build/push, check-cluster.sh |
| Teammate 3 | TODO | TODO | kitchen-worker, stats-api, k8s manifests, CD pipeline, check-databases.sh, ops-monitor |

- Jira board: TODO (link)
- Both websites: https://dhaba-prod.duckdns.org (production), https://dhaba-staging.duckdns.org (staging). These DuckDNS names point at the VM's public IP (16.179.57.193), which is hardcoded in DuckDNS, so they break if the IP changes; an Elastic IP is the proper fix.
- Actions tab: TODO (link)

## Services
| Service | Stack | Port | Notes |
|---|---|---|---|
| web | React (Vite) on Nginx | 8080 | static bundle; calls same-host /api/... |
| menu-api | Python (FastAPI) | 8000 | reads menu from Postgres, caches in Redis |
| orders-api | Go | 8080 | writes orders to Postgres, pushes to Redis queue |
| kitchen-worker | Java (Spring Boot) | none | drains Redis queue, updates Postgres, heartbeats to Redis every 10s |
| stats-api | PHP (Laravel-style, PHP-FPM + Nginx) | 8080 | reads live numbers from Redis |
| postgres | PostgreSQL (StatefulSet) | 5432 | orders + menu, persistent volume |
| redis | Redis (StatefulSet) | 6379 | cache + job queue, AOF persistence |
| ops-monitor | Bash in Alpine | none | runs scripts/monitor/*.sh on a CronJob |

## ECR image pull credentials (C9)
ECR login tokens expire after 12 hours. We refresh the
`regcred` image-pull secret in staging and production two ways:
1. **Every deploy**: the deploy workflow step runs
   `aws ecr get-login-password` (via the same GitHub OIDC role used for
   pushing) and recreates the k8s secret right before `kubectl apply`.
2. **Every 6 hours**: a CronJob inside the cluster (`ops` namespace) does
   the same refresh so a pod rescheduled overnight, with no deploy in
   between, doesn't hit `ErrImagePull`.

   **The choice to discuss with the trainer:** the in-cluster CronJob
   needs *some* way to call AWS. Two options:
   - Give the CronJob's ServiceAccount an IRSA-style role (if the cluster
     supports IAM Roles for Service Accounts) — no long-lived AWS keys
     anywhere, same OIDC trust model as GitHub Actions.
   - If IRSA isn't available on this cluster (plain k3s VMs, not EKS),
     store a narrowly-scoped AWS access key (ECR read-only, nothing else)
     as a Kubernetes Secret, rotated manually every 90 days, and accept
     that as the one place a long-lived credential lives in the cluster.
   **Risk of option 2:** a long-lived key sitting in `ops` namespace is a
   bigger blast radius than OIDC's short-lived tokens — if the cluster is
   compromised, that key is usable from anywhere until rotated. We are
   using **option 2** for this exercise since our 3-node k3s cluster is
   not EKS and has no OIDC provider for IRSA; TODO once decided — confirm
   here and note the rotation owner.

## Local development
Each service's Dockerfile builds standalone; see `docker-compose.yml`
(TODO, Phase 1 stretch) or run `docker build` per service directory.

## CI/CD
See `.github/workflows/`. Pipeline stages: static analysis → unit tests →
build & push to ECR → deploy to staging (auto) → deploy to production
(after approval). Full details in the architecture doc shared in Jira.
