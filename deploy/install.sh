#!/bin/bash
# Install the deploy scripts from this checkout to $HOME.
#
#   bash ~/ns-build/deploy/install.sh
#
# The scripts must run from OUTSIDE the checkout: deploy.sh rewrites the
# checkout with `git checkout`, and rewriting a script bash is still reading
# corrupts execution. Re-run this after pulling changes to deploy/.
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
DEST="$HOME"

for f in deploy.sh rollback.sh; do
  install -m 755 "$SRC/$f" "$DEST/$f"
  echo "installed $DEST/$f"
done

if [ -f "$DEST/deploy.conf" ]; then
  echo "kept existing $DEST/deploy.conf"
else
  install -m 600 "$SRC/deploy.conf.example" "$DEST/deploy.conf"
  echo "created $DEST/deploy.conf from the example — EDIT IT before deploying"
fi

echo
echo "next: verify ~/deploy.conf, then run  ~/deploy.sh <ref>"
