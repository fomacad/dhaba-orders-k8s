#!/usr/bin/env bash
# C13: post one line to #TEAM-alerts. Never fails the job (a broken webhook must not
# block a deployment), and prints the message so it is also in the run log.
# Usage: SLACK_WEBHOOK_URL=... scripts/notify-slack.sh "message"
set -uo pipefail
MSG="${1:?usage: notify-slack.sh <message>}"
echo "slack: $MSG"
if [ -z "${SLACK_WEBHOOK_URL:-}" ]; then
  echo "SLACK_WEBHOOK_URL is not set - message not sent" >&2
  exit 0
fi
PAYLOAD=$(MSG="$MSG" python3 -c 'import json, os; print(json.dumps({"text": os.environ["MSG"]}))')
curl -fsS --max-time 10 -X POST -H 'Content-Type: application/json' \
  --data "$PAYLOAD" "$SLACK_WEBHOOK_URL" >/dev/null || echo "slack post failed" >&2
exit 0
