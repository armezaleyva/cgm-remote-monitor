#!/bin/bash
# Build, test, and deploy a git ref of this repo to the production host.
#
# Usage: ~/deploy.sh [git-ref]        (default: master)
#   SKIP_TESTS=1   deploy without the unit-test gate (discouraged)
#   SKIP_BACKUP=1  deploy without a pre-deploy database dump (discouraged)
#   DEPLOY_CONF=/path/to/conf   override config location
#
# Run the INSTALLED copy (~/deploy.sh), not the one in the checkout — see
# deploy/README.md. Host-specific settings live in ~/deploy.conf.
set -euo pipefail

CONF="${DEPLOY_CONF:-$HOME/deploy.conf}"
[ -f "$CONF" ] || { echo "ERROR: no config at $CONF (copy deploy/deploy.conf.example)"; exit 1; }
# shellcheck disable=SC1090
. "$CONF"

: "${PUBLIC_HOST:?PUBLIC_HOST must be set in $CONF}"
: "${BUILD_DIR:?BUILD_DIR must be set in $CONF}"
: "${STACK_DIR:?STACK_DIR must be set in $CONF}"
IMAGE_REPO="${IMAGE_REPO:-nightscout-tz}"
KEEP_IMAGES="${KEEP_IMAGES:-5}"
HEALTH_TRIES="${HEALTH_TRIES:-60}"
BACKUP_SCRIPT="${BACKUP_SCRIPT:-}"

REF="${1:-master}"
ENV_FILE="$STACK_DIR/.env"
TEST_MONGO=ns-test-mongo
LOG="$HOME/deploy.log"

log()  { printf '%s %s\n' "$(date -Is)" "$*" | tee -a "$LOG"; }
fail() { log "ERROR: $*"; exit 1; }
cleanup() { docker rm -f "$TEST_MONGO" >/dev/null 2>&1 || true; }
trap cleanup EXIT

# Refuse to run from inside the checkout: this script rewrites BUILD_DIR with
# `git checkout`, which would change its own file while bash is still reading it.
SELF="$(readlink -f "$0")"
case "$SELF" in
  "$(readlink -f "$BUILD_DIR")"/*)
    fail "refusing to run from inside $BUILD_DIR — install it first: bash $BUILD_DIR/deploy/install.sh, then run ~/deploy.sh" ;;
esac

health() {
  curl -sk -o /dev/null -w '%{http_code}' -H "Host: $PUBLIC_HOST" \
    --max-time 5 "https://127.0.0.1/api/v1/status.json" 2>/dev/null || echo 000
}

# The app returns 401 unauthenticated when AUTH_DEFAULT_ROLES=denied, which is
# the correct healthy response — treat it and 200 as success.
wait_healthy() {
  local tries="$1" code=000 i
  for i in $(seq 1 "$tries"); do
    code=$(health)
    if [ "$code" = "401" ] || [ "$code" = "200" ]; then echo "$code"; return 0; fi
    sleep 2
  done
  echo "$code"; return 1
}

log "=== deploy start: ref=$REF ==="

CURRENT_TAG=$(sed -n 's/^NS_IMAGE_TAG=//p' "$ENV_FILE" | head -1)
[ -n "$CURRENT_TAG" ] || fail "NS_IMAGE_TAG missing from $ENV_FILE — see deploy/README.md"
log "currently deployed: $IMAGE_REPO:$CURRENT_TAG"

# --- 1. resolve and check out the ref -------------------------------------
cd "$BUILD_DIR"
git fetch --all --prune --tags --quiet
if git rev-parse --verify --quiet "origin/$REF^{commit}" >/dev/null; then
  FULL=$(git rev-parse "origin/$REF^{commit}")
elif git rev-parse --verify --quiet "$REF^{commit}" >/dev/null; then
  FULL=$(git rev-parse "$REF^{commit}")
else
  fail "cannot resolve git ref: $REF"
fi
SHA=$(git rev-parse --short=8 "$FULL")
git checkout --detach --quiet "$FULL"
log "building $IMAGE_REPO:$SHA — $(git log -1 --oneline)"

# --- 2. build --------------------------------------------------------------
BUILD_LOG="$BUILD_DIR/build-$SHA.log"
START=$(date +%s)
if ! docker build -t "$IMAGE_REPO:$SHA" . >"$BUILD_LOG" 2>&1; then
  tail -40 "$BUILD_LOG"
  fail "docker build failed — prod untouched, still on $CURRENT_TAG (full log: $BUILD_LOG)"
fi
log "build succeeded in $(( $(date +%s) - START ))s"

# --- 3. test gate: run the suite inside the image we are about to ship -----
# The image ships devDependencies (the Dockerfile omits only optional deps), so
# it can test itself. tests/ci.test.env points at 127.0.0.1:27017/testdb, so the
# test container joins the throwaway mongo's network namespace to reach it.
if [ "${SKIP_TESTS:-0}" = "1" ]; then
  log "WARNING: test gate skipped by SKIP_TESTS=1"
else
  cleanup
  docker run -d --name "$TEST_MONGO" mongo:4.4 >/dev/null
  for i in $(seq 1 30); do
    docker exec "$TEST_MONGO" mongo --quiet --eval 'db.runCommand({ping:1}).ok' >/dev/null 2>&1 && break
    sleep 1
  done
  log "running unit suite inside $IMAGE_REPO:$SHA"
  TEST_START=$(date +%s)
  if ! docker run --rm --network "container:$TEST_MONGO" "$IMAGE_REPO:$SHA" npm run test:unit:ci; then
    fail "tests FAILED — nothing deployed, prod still on $CURRENT_TAG"
  fi
  log "tests passed in $(( $(date +%s) - TEST_START ))s"
  cleanup
fi

# --- 4. pre-deploy backup --------------------------------------------------
if [ "${SKIP_BACKUP:-0}" = "1" ] || [ -z "$BACKUP_SCRIPT" ]; then
  log "WARNING: pre-deploy backup skipped"
else
  log "taking pre-deploy database backup"
  "$BACKUP_SCRIPT" || fail "pre-deploy backup failed — aborting (SKIP_BACKUP=1 to override)"
fi

# --- 5. swap ---------------------------------------------------------------
echo "$CURRENT_TAG" > "$HOME/.previous-tag"
sed -i "s/^NS_IMAGE_TAG=.*/NS_IMAGE_TAG=$SHA/" "$ENV_FILE"
chmod 600 "$ENV_FILE"
cd "$STACK_DIR"
log "swapping container to $IMAGE_REPO:$SHA (brief downtime while it restarts)"
docker compose up -d nightscout

# --- 6. health check, auto-rollback on failure -----------------------------
log "waiting for the app to answer"
if CODE=$(wait_healthy "$HEALTH_TRIES"); then
  log "healthy: HTTP $CODE on $IMAGE_REPO:$SHA"
else
  log "health check FAILED (last HTTP $CODE) — ROLLING BACK to $CURRENT_TAG"
  docker compose logs --tail 40 nightscout || true
  sed -i "s/^NS_IMAGE_TAG=.*/NS_IMAGE_TAG=$CURRENT_TAG/" "$ENV_FILE"
  chmod 600 "$ENV_FILE"
  docker compose up -d nightscout
  if RC=$(wait_healthy 30); then
    fail "deploy of $SHA failed; rolled back to $CURRENT_TAG and it is healthy (HTTP $RC)"
  else
    fail "deploy of $SHA failed AND rollback to $CURRENT_TAG is not answering (HTTP $RC) — INVESTIGATE NOW"
  fi
fi

# Boot failures do not crash the app; they accumulate in ctx.bootErrors and the
# server serves an error page instead, which would still answer the health check.
if docker compose logs --tail 200 nightscout 2>/dev/null | grep -qiE 'boot error|booterror'; then
  log "WARNING: boot errors in logs — the app may be serving an error page. Check: docker compose logs nightscout"
fi

# --- 7. prune old images, keeping recent rollback targets ------------------
docker images "$IMAGE_REPO" --format '{{.Tag}}' | tail -n +$((KEEP_IMAGES + 1)) | while read -r t; do
  [ "$t" = "$CURRENT_TAG" ] && continue
  docker rmi "$IMAGE_REPO:$t" >/dev/null 2>&1 && log "pruned old image $IMAGE_REPO:$t" || true
done

log "=== deploy OK: $CURRENT_TAG -> $SHA (rollback: ~/rollback.sh) ==="
