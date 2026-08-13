# Deployment scripts

Build-test-deploy tooling for a self-hosted instance of this fork. These scripts
are host-agnostic: everything site-specific lives in `deploy.conf`, which is
**not** committed.

## The loop

```bash
git checkout -b wip/my-change
# ...edit, commit...
git push -u origin wip/my-change

ssh <host> ./deploy.sh wip/my-change   # build, test, deploy that ref
ssh <host> ./rollback.sh               # undo, if needed

git checkout master && git merge wip/my-change && git push   # promote once proven
```

`deploy.sh` accepts any git ref — branch, tag, or SHA — and defaults to `master`.
It resolves `origin/<ref>` first, then a bare ref.

## What a deploy does

1. Fetch and `git checkout --detach` the resolved commit in `BUILD_DIR`.
2. `docker build -t $IMAGE_REPO:<short-sha>`; the full log goes to
   `BUILD_DIR/build-<sha>.log`.
3. **Test gate** — start a throwaway MongoDB and run the unit suite *inside the
   image about to ship*. This works because the `Dockerfile` runs
   `npm ci --omit=optional`, which keeps devDependencies, so the production image
   contains mocha and `tests/`. `tests/ci.test.env` points at
   `127.0.0.1:27017/testdb`, so the test container joins the throwaway mongo's
   network namespace rather than needing a rewritten config. The `testdb` name
   also satisfies the `tests/lib/production-safety.js` preflight.
4. Pre-deploy database dump via `BACKUP_SCRIPT`.
5. Write the new tag into the stack's `.env` and `docker compose up -d nightscout`.
6. Health check; **auto-rollback** to the previous tag if it fails.
7. Prune old images, keeping `KEEP_IMAGES` rollback targets.

A build or test failure aborts before anything live is touched. Progress is
appended to `~/deploy.log`; the replaced tag is saved to `~/.previous-tag`.

## Health check: 401 is success

The check issues `https://127.0.0.1/api/v1/status.json` with a `Host:` header, so
it exercises the reverse proxy without depending on external DNS. When the
instance runs `AUTH_DEFAULT_ROLES=denied`, an unauthenticated request correctly
returns **401** — the script treats 401 and 200 as healthy. Do not "fix" a 401
from a deployed instance without checking whether it is simply auth working.

Note that boot failures do not crash the app: they accumulate in `ctx.bootErrors`
and the server serves an error page, which still answers the health check. The
script greps the logs for boot errors and warns, but a green deploy plus that
warning means the app is up and broken.

## Host setup (once)

The stack's `docker-compose.yml` must take the image tag from the environment:

```yaml
services:
  nightscout:
    image: nightscout-tz:${NS_IMAGE_TAG}
```

with `NS_IMAGE_TAG=<current-tag>` in the `.env` beside it. Deploy and rollback
then set one variable instead of rewriting YAML, which is what makes automatic
rollback reliable.

Then install the scripts:

```bash
bash ~/ns-build/deploy/install.sh   # copies to $HOME, seeds ~/deploy.conf
$EDITOR ~/deploy.conf               # set PUBLIC_HOST and paths
```

**Run the installed copy at `~/deploy.sh`, not the one in the checkout.**
`deploy.sh` rewrites the checkout with `git checkout`, and rewriting a script
while bash is still reading it corrupts execution — so the script refuses to run
from inside `BUILD_DIR`. Re-run `install.sh` after pulling changes to `deploy/`.

## Escape hatches

`SKIP_TESTS=1` and `SKIP_BACKUP=1` bypass the corresponding gate. Both log a
warning. They exist for emergencies; reaching for them routinely defeats the
point of the loop.

## Expected timings

On a 1-OCPU aarch64 host: build ~195s (no layer cache — `ADD . /opt/app` sits
above `npm ci`, so every build reinstalls), unit gate ~14s, swap and health check
~18s. Total under four minutes, with **10–15 seconds of downtime** while the
container restarts.
