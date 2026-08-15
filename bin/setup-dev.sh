#!/bin/sh
#
# Fork-local developer setup.
#
# Gets a fresh checkout to the point where `npm run lint` and `npm run test:unit`
# actually run, so changes can be verified before they reach the deploy gate.
#
# Works in Git Bash on Windows and in any POSIX shell on Linux/macOS.
# Safe to re-run: it never overwrites an existing my.env or my.test.env.
#
# Usage:
#   bin/setup-dev.sh                 full setup, including the webpack bundle
#   bin/setup-dev.sh --fast          skip the bundle; enough for lint + unit tests
#   bin/setup-dev.sh --skip-install  only create the env files
#   bin/setup-dev.sh --verify        run lint and the unit suite when finished
#
# NOTE: this is not bin/setup.sh. That one is upstream's Vagrant/Ubuntu
# provisioner and it installs Node 8, which this project no longer supports.

set -eu

# ---------------------------------------------------------------- presentation

if [ -t 1 ]; then
  B=$(printf '\033[1m'); R=$(printf '\033[31m'); Y=$(printf '\033[33m')
  G=$(printf '\033[32m'); Z=$(printf '\033[0m')
else
  B=''; R=''; Y=''; G=''; Z=''
fi

step () { printf '\n%s==> %s%s\n' "$B" "$1" "$Z"; }
info () { printf '    %s\n' "$1"; }
good () { printf '    %sok%s %s\n' "$G" "$Z" "$1"; }
warn () { printf '    %swarning%s %s\n' "$Y" "$Z" "$1"; }
die  () { printf '\n%serror%s %s\n\n' "$R" "$Z" "$1" >&2; exit 1; }

# ---------------------------------------------------------------------- args

SKIP_INSTALL=0
FAST=0
VERIFY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --skip-install) SKIP_INSTALL=1 ;;
    --fast)         FAST=1 ;;
    --verify)       VERIFY=1 ;;
    -h|--help)      sed -n '3,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)              die "unknown option: $1 (try --help)" ;;
  esac
  shift
done

REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$REPO_ROOT"

# ------------------------------------------------------------------ platform

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) PLATFORM=windows ;;
  Darwin)               PLATFORM=macos ;;
  *)                    PLATFORM=linux ;;
esac

node_install_hint () {
  case "$PLATFORM" in
    windows) info 'winget install OpenJS.NodeJS.LTS' ;;
    macos)   info 'brew install node@22' ;;
    linux)   info 'see https://nodejs.org/en/download/package-manager/ (or use nvm)' ;;
  esac
  info 'Node 22 is the version the Dockerfile and CI both use.'
}

# -------------------------------------------------------------- 1. toolchain

step 'Checking the toolchain'

command -v node >/dev/null 2>&1 || {
  printf '\n%serror%s Node.js is not installed or not on PATH.\n\n' "$R" "$Z" >&2
  node_install_hint
  printf '\n'
  exit 1
}
command -v npm >/dev/null 2>&1 || die 'npm is not installed or not on PATH.'

NODE_VERSION=$(node -p 'process.versions.node')
NODE_MAJOR=$(node -p 'process.versions.node.split(".")[0]')
NPM_VERSION=$(npm -v)
NPM_MAJOR=$(printf '%s' "$NPM_VERSION" | cut -d. -f1)

# package.json engines: node >=20.x, npm >=10.x
[ "$NODE_MAJOR" -ge 20 ] || {
  printf '\n%serror%s Node %s is too old; package.json requires >= 20.\n\n' "$R" "$Z" "$NODE_VERSION" >&2
  node_install_hint
  printf '\n'
  exit 1
}
[ "$NPM_MAJOR" -ge 10 ] || die "npm $NPM_VERSION is too old; package.json requires >= 10. Try: npm install -g npm@latest"

good "node $NODE_VERSION"
good "npm $NPM_VERSION"

case "$NODE_MAJOR" in
  20|22|24) ;;
  *) warn "Node $NODE_MAJOR is outside the CI matrix (20, 22, 24). It may still work." ;;
esac

# ----------------------------------------------------------- 2. dependencies

if [ "$SKIP_INSTALL" -eq 1 ]; then
  step 'Skipping dependency install (--skip-install)'
else
  step 'Installing dependencies'
  if [ "$FAST" -eq 1 ]; then
    info 'npm ci --ignore-scripts (no webpack bundle; lint and unit tests do not need it)'
    npm ci --ignore-scripts || die 'npm ci failed. If a native module failed to build, try: npm ci --omit=optional'
  else
    info 'npm ci  (postinstall builds the production webpack bundle, so this is slow)'
    npm ci || die 'npm ci failed. If a native module failed to build, retry with --fast, or: npm ci --omit=optional'
  fi
  good 'dependencies installed'
fi

# ------------------------------------------------------------ 3. environment

step 'Creating environment files'

# Values mirror the Makefile's `my.test.env` target so both paths agree.
if [ -f my.test.env ]; then
  good 'my.test.env already exists, leaving it alone'
else
  cat > my.test.env <<'EOF'
MONGO_CONNECTION=mongodb://localhost:27017/test_db
CUSTOMCONNSTR_mongo_collection=test_sgvs
CUSTOMCONNSTR_mongo_settings_collection=test_settings
API_SECRET=test-secret-key
AUTH_FAIL_DELAY=50
INSECURE_USE_HTTP=true
EOF
  good 'wrote my.test.env (gitignored)'
fi

if [ -f my.env ]; then
  good 'my.env already exists, leaving it alone'
elif [ -f docs/example-template.env ]; then
  cp docs/example-template.env my.env
  good 'wrote my.env from docs/example-template.env (gitignored)'
  warn 'my.env needs editing before `npm run dev`: set a real Mongo connection and API_SECRET.'
else
  warn 'docs/example-template.env is missing; skipped my.env.'
fi

# ----------------------------------------------------------------- 4. mongo

step 'Checking MongoDB'

MONGO_UP=0
if [ "$SKIP_INSTALL" -eq 1 ] && [ ! -d node_modules ]; then
  warn 'skipped (no node_modules yet)'
else
  if node -e '
    var s = require("net").createConnection(27017, "127.0.0.1");
    s.setTimeout(1500);
    s.on("connect", function () { s.end(); process.exit(0); });
    s.on("timeout", function () { s.destroy(); process.exit(1); });
    s.on("error",   function () { process.exit(1); });
  ' 2>/dev/null; then
    MONGO_UP=1
    good 'reachable on localhost:27017'
  else
    warn 'not reachable on localhost:27017'
    info 'Unit tests do not need it. Integration tests do. To start one:'
    info '  docker run -d --name ns-test-mongo -p 27017:27017 mongo:4.4'
    info '(4.4 is what production pins, and the floor of the CI matrix.)'
  fi
fi

# ---------------------------------------------------------------- 5. verify

if [ "$VERIFY" -eq 1 ]; then
  step 'Running lint'
  npm run lint

  step 'Running the unit suite'
  npm run test:unit
fi

# ------------------------------------------------------------------ 6. done

step 'Ready'
info 'npm run lint                     eslint, lib/ only'
info 'npm run test:unit                fast suite, no MongoDB needed'
if [ "$MONGO_UP" -eq 1 ]; then
  info 'npm run test:integration         api / storage / websocket suites'
else
  info 'npm run test:integration         (needs MongoDB — see above)'
fi
info 'TEST=moodoftheday npm run test-single    one suite by name'
info 'npm run dev                      dev server on PORT (default 1337)'
if [ "$FAST" -eq 1 ]; then
  printf '\n'
  warn 'Ran with --fast, so there is no webpack bundle. Run `npm run bundle` before `npm start`.'
fi
printf '\n'
