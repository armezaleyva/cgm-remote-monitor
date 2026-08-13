#!/bin/bash
# Roll production back to a previously built image tag.
#
# Usage: ~/rollback.sh [tag]   (default: the tag replaced by the last deploy)
set -euo pipefail

CONF="${DEPLOY_CONF:-$HOME/deploy.conf}"
[ -f "$CONF" ] || { echo "ERROR: no config at $CONF (copy deploy/deploy.conf.example)"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

: "${PUBLIC_HOST:?PUBLIC_HOST must be set in $CONF}"
: "${STACK_DIR:?STACK_DIR must be set in $CONF}"
IMAGE_REPO="${IMAGE_REPO:-nightscout-tz}"

ENV_FILE="$STACK_DIR/.env"
LOG="$HOME/deploy.log"

list_tags() {
  echo "available image tags:"
  docker images "$IMAGE_REPO" --format '  {{.Tag}}  ({{.CreatedSince}})'
}

TARGET="${1:-$(cat "$HOME/.previous-tag" 2>/dev/null || true)}"
if [ -z "$TARGET" ]; then
  echo "usage: ~/rollback.sh <tag>   (no previous tag recorded)"
  list_tags
  exit 1
fi

if ! docker image inspect "$IMAGE_REPO:$TARGET" >/dev/null 2>&1; then
  echo "ERROR: no such image $IMAGE_REPO:$TARGET"
  list_tags
  exit 1
fi

CUR=$(sed -n 's/^NS_IMAGE_TAG=//p' "$ENV_FILE" | head -1)
printf '%s rollback: %s -> %s\n' "$(date -Is)" "$CUR" "$TARGET" | tee -a "$LOG"

# Record the tag we are leaving, so a second rollback returns here.
echo "$CUR" > "$HOME/.previous-tag"
sed -i "s/^NS_IMAGE_TAG=.*/NS_IMAGE_TAG=$TARGET/" "$ENV_FILE"
chmod 600 "$ENV_FILE"

cd "$STACK_DIR"
docker compose up -d nightscout

CODE=000
for i in $(seq 1 30); do
  CODE=$(curl -sk -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOST" \
    --max-time 5 "https://127.0.0.1/api/v1/status.json" 2>/dev/null || echo 000)
  if [ "$CODE" = "401" ] || [ "$CODE" = "200" ]; then break; fi
  sleep 2
done
printf '%s rollback complete: now on %s (HTTP %s)\n' "$(date -Is)" "$TARGET" "$CODE" | tee -a "$LOG"
[ "$CODE" = "401" ] || [ "$CODE" = "200" ]
