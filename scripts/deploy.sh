#!/usr/bin/env bash
# Deploy Dhaba Orders to one environment, smoke-test it, and roll back if anything fails.
#
# Usage: scripts/deploy.sh <staging|production> <commit-sha>
#   Default: services whose image exists in ECR for <commit-sha> get that tag;
#            every other service keeps the image that is running now.
#   PIN_IMAGES="web=<image> menu-api=<image> ...": deploy exactly these images instead.
#            Production uses this with the images that passed staging (never a new
#            build), and scripts/rollback.sh uses it with the previous release.
#
# Needs: AWS_REGION, TEAM, KUBECONFIG (the deployer ServiceAccount), aws, kubectl, curl.
# The runner is on the VM, where port 443 forwards to the ingress (smoke tests use https).
set -euo pipefail

NS="${1:?usage: deploy.sh <staging|production> <sha>}"
SHA="${2:?usage: deploy.sh <staging|production> <sha>}"
PIN_IMAGES="${PIN_IMAGES:-}"
: "${AWS_REGION:?set AWS_REGION}" "${TEAM:?set TEAM}"
BASE_URL="${BASE_URL:-http://localhost}"
SERVICES=(web menu-api orders-api stats-api kitchen-worker)

case "$NS" in
  staging)    HOST="dhaba-staging.duckdns.org" ;;
  production) HOST="dhaba-prod.duckdns.org" ;;
  *) echo "unknown environment: $NS" >&2; exit 2 ;;
esac

ACCOUNT=$(aws sts get-caller-identity --query Account --output text)
REG="${ACCOUNT}.dkr.ecr.${AWS_REGION}.amazonaws.com"
summary() { echo "$*" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"; echo "$*"; }

current_image() {
  kubectl -n "$1" get deploy "$2" -o jsonpath='{.spec.template.spec.containers[0].image}' 2>/dev/null || true
}

# ---------------------------------------------------------------- which image per service
declare -A BEFORE TARGET PINNED
read -r -a PAIRS <<< "$PIN_IMAGES"
for pair in "${PAIRS[@]}"; do PINNED[${pair%%=*}]="${pair#*=}"; done
for s in "${SERVICES[@]}"; do
  BEFORE[$s]=$(current_image "$NS" "$s")
  if [ -n "$PIN_IMAGES" ]; then
    TARGET[$s]="${PINNED[$s]:-${BEFORE[$s]}}"
  elif aws ecr describe-images --repository-name "dhaba-${TEAM}/${s}" --image-ids imageTag="$SHA" >/dev/null 2>&1; then
    TARGET[$s]="${REG}/dhaba-${TEAM}/${s}:${SHA}"
  else
    TARGET[$s]="${BEFORE[$s]}"
  fi
done

rollback() {
  summary "### :x: $NS: $1 - rolling back"
  for s in "${SERVICES[@]}"; do
    if [ -n "${BEFORE[$s]}" ] && [ "${BEFORE[$s]}" != "${TARGET[$s]}" ]; then
      kubectl -n "$NS" set image "deploy/$s" "$s=${BEFORE[$s]}"
      summary "- rolled back $s to ${BEFORE[$s]##*:}"
    fi
  done
  for s in "${SERVICES[@]}"; do
    kubectl -n "$NS" rollout status "deploy/$s" --timeout=180s || true
  done
  echo "rolled_back=true" >> "${GITHUB_OUTPUT:-/dev/null}"
  exit 1
}

# ---------------------------------------------------------------- pull secret (C9)
# ECR tokens expire after 12 h: refresh before every deployment
kubectl -n "$NS" create secret docker-registry regcred \
  --docker-server="$REG" --docker-username=AWS \
  --docker-password="$(aws ecr get-login-password --region "$AWS_REGION")" \
  --dry-run=client -o yaml | kubectl apply -f -

# ---------------------------------------------------------------- render and apply
RENDERED=$(mktemp)
trap 'rm -f "$RENDERED"' EXIT
kubectl kustomize "k8s/overlays/$NS" > "$RENDERED"
for s in "${SERVICES[@]}"; do
  if [ -n "${TARGET[$s]}" ]; then
    sed -i -E "s#image: [^[:space:]]*/dhaba-${TEAM}/${s}:[^[:space:]]+#image: ${TARGET[$s]}#" "$RENDERED"
  fi
done

summary "### Deploying to $NS (commit ${SHA:0:7})"
for s in "${SERVICES[@]}"; do summary "- $s: ${TARGET[$s]##*:}"; done

kubectl apply -f "$RENDERED" || rollback "kubectl apply failed"

# ---------------------------------------------------------------- wait, with a time limit
for s in "${SERVICES[@]}"; do
  kubectl -n "$NS" rollout status "deploy/$s" --timeout=180s || rollback "rollout of $s did not finish"
done
for s in postgres redis; do
  kubectl -n "$NS" rollout status "statefulset/$s" --timeout=180s || rollback "$s is not ready"
done

# ---------------------------------------------------------------- smoke tests
# Test through the VM's port 443 forwarder. --resolve points the DuckDNS name at
# localhost; -k because a new host serves the ingress default certificate until
# cert-manager issues the real one (this checks routing, not the certificate).
BASE_URL="https://$HOST"
api() { curl -fsSk --max-time 5 --resolve "$HOST:443:127.0.0.1" "$@"; }

# the ingress controller takes a moment to pick up a changed Ingress
UP=""
for _ in $(seq 1 30); do
  if api "$BASE_URL/" >/dev/null 2>&1; then UP=yes; break; fi
  sleep 2
done
[ -n "$UP" ] || rollback "smoke: web page not served"
# (responses go into variables first: "curl | grep -q" can fail under pipefail)
MENU=$(api "$BASE_URL/api/menu") || MENU=""
grep -q '"items":\[{' <<<"$MENU" || rollback "smoke: menu did not load"

POSTED=$(api -X POST -H 'Content-Type: application/json' -d '{"dish":"Smoke Test"}' "$BASE_URL/api/orders") || POSTED=""
ID=$(sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' <<<"$POSTED")
[ -n "$ID" ] || rollback "smoke: could not place an order"

READY=""
for _ in $(seq 1 30); do
  ORDERS=$(api "$BASE_URL/api/orders") || ORDERS=""
  if grep -q "\"id\":${ID},\"dish\":\"Smoke Test\",\"status\":\"ready\"" <<<"$ORDERS"; then
    READY=yes; break
  fi
  sleep 1
done
[ -n "$READY" ] || rollback "smoke: order $ID never reached 'ready' (kitchen-worker?)"

STATS=$(api "$BASE_URL/api/stats") || STATS=""
grep -q '"orders_per_minute"' <<<"$STATS" || rollback "smoke: stats did not respond"

# ---------------------------------------------------------------- record the release
# images=... is used by the production job (same images as staging);
# release-history.previous is what the rollback button returns to.
IMAGES=""
for s in "${SERVICES[@]}"; do IMAGES+="$s=${TARGET[$s]} "; done
echo "images=${IMAGES% }" >> "${GITHUB_OUTPUT:-/dev/null}"
PREVIOUS=""
CHANGED=""
for s in "${SERVICES[@]}"; do
  PREVIOUS+="$s=${BEFORE[$s]} "
  if [ "${BEFORE[$s]}" != "${TARGET[$s]}" ]; then CHANGED=yes; fi
done
if [ -n "$CHANGED" ]; then
  kubectl -n "$NS" create configmap release-history \
    --from-literal=previous="${PREVIOUS% }" --from-literal=current="${IMAGES% }" \
    --dry-run=client -o yaml | kubectl apply -f -
fi

summary "### :white_check_mark: $NS deployed and smoke tests passed (order $ID went new -> ready)"
