# Builds tconnectsync for arm64.
#
# Why this exists instead of upstream's image or upstream's Dockerfile:
#
#  1. Upstream publishes amd64-only images. Both ghcr.io/jwoglom/tconnectsync
#     and docker.io/jwoglom/tconnectsync return a single-architecture manifest
#     (architecture: amd64), so neither runs natively on our aarch64 host.
#
#  2. Upstream's own Dockerfile does `pip install pipenv` unpinned and then
#     `pipenv install --deploy`. `--deploy` exists to abort when Pipfile.lock's
#     recorded Pipfile hash does not match the Pipfile. Current pipenv computes
#     that hash differently from whatever produced the committed lockfile, so
#     the build aborts with DeployException — on any architecture, not just
#     ours. Rebuilding upstream's Dockerfile today fails on amd64 too.
#
# The dependency set (setup.cfg install_requires) is ordinary and setup.cfg
# already declares a console_scripts entry point, so plain pip is enough and
# removes the pipenv failure mode entirely.
#
# Build against a tconnectsync checkout — the tag is the reproducibility
# anchor, since pip resolves dependency versions at build time:
#
#   git -C ~/tconnectsync-build checkout v3.0.1
#   docker build -f deploy/tconnectsync/Dockerfile \
#                -t tconnectsync:v3.0.1 ~/tconnectsync-build

FROM python:3.11-slim

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONFAULTHANDLER=1 \
    PYTHONUNBUFFERED=1

# gcc is a fallback: lxml, cryptography and cffi all publish aarch64 wheels,
# but the resolved pin set can move and compiling beats failing.
RUN apt-get update \
 && apt-get install -y --no-install-recommends gcc \
 && rm -rf /var/lib/apt/lists/*

WORKDIR /src
COPY . .
RUN pip install --no-cache-dir .

RUN useradd --create-home appuser
USER appuser
WORKDIR /home/appuser

# console_scripts entry point from setup.cfg; equivalent to `python3 main.py`.
ENTRYPOINT ["tconnectsync"]
