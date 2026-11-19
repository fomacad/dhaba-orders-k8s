#!/usr/bin/env bash
# C13: roll an environment back to the release before the current one.
# Usage: scripts/rollback.sh <staging|production>
# Reads release-history.previous (written by deploy.sh) and redeploys exactly those
# images with deploy.sh, so the rollback is also smoke-tested.
set -euo pipefail
NS="${1:?usage: rollback.sh <staging|production>}"
PREV=$(kubectl -n "$NS" get configmap release-history -o jsonpath='{.data.previous}' 2>/dev/null || true)
if [ -z "$PREV" ]; then
  echo "No previous release recorded for $NS - nothing to roll back to." >&2
  exit 1
fi
echo "Rolling $NS back to: $PREV"
PIN_IMAGES="$PREV" exec bash "$(dirname "$0")/deploy.sh" "$NS" rollback
