#!/bin/bash
# Configures DevSpace via its OLD env-var system, not config.jsonc.
#
# The published npm package (@waishnav/devspace@1.0.8) predates the
# config.jsonc consolidation described in the project's main-branch
# docs/configuration.md ("Durable environment settings were removed in
# v1.1"). 1.0.8 reads HOST/PORT/DEVSPACE_ALLOWED_ROOTS/etc. directly and
# silently ignores any config.jsonc/DEVSPACE_CONFIG_DIR -- confirmed by
# testing: writing a config.jsonc with an unusual port had zero effect on
# the version actually installed. If a future image bump upgrades past
# v1.1, this whole file needs revisiting against the newer config system.
set -euo pipefail

export HOST="0.0.0.0"
export PORT="7676"

# Multi-repo support: DEVSPACE_ALLOWED_ROOTS accepts a comma-separated list
# (confirmed against the v1.0.8-tagged upstream docs -- the main-branch docs
# describe a newer, unreleased-as-of-1.0.8 config model instead). Each repo
# this container serves is bind-mounted as its own subdirectory under
# /repos in docker-compose.yml; this loop discovers whatever is actually
# mounted there instead of hardcoding names, so adding a new repo later is
# just one more `volumes:` line + .env var + `docker compose up -d` --
# no entrypoint change needed.
roots=""
for repo_dir in /repos/*/; do
    repo_dir="${repo_dir%/}"
    [ -d "$repo_dir" ] || continue
    # Same reasoning as before, per repo: the bind-mounted repo is owned by
    # whatever UID/GID the host filesystem reports (via Docker Desktop's
    # Windows/WSL2 bind-mount translation), which essentially never matches
    # this container's UID 10001. git's dubious-ownership protection then
    # refuses every git operation inside it with "detected dubious
    # ownership" -- confirmed by testing (ChatGPT's own `bash` tool call
    # failed with exactly this error on a fresh open_workspace). This does
    # not weaken the isolation posture: it only tells git to trust the
    # specific bind-mounted paths this container was already explicitly
    # given, not any other directory.
    git config --global --add safe.directory "$repo_dir"
    roots="${roots:+$roots,}$repo_dir"
done
export DEVSPACE_ALLOWED_ROOTS="$roots"

# Only set DEVSPACE_PUBLIC_BASE_URL when a real value is provided.
# devspace 1.0.8 crashes with "Invalid URL" if this variable is merely
# PRESENT with an empty string value -- confirmed by testing. Reading from
# our own DEVSPACE_ISOLATION_PUBLIC_BASE_URL (set in docker-compose.yml)
# means a blank .env value never leaks into devspace's actual process
# environment as an empty-but-present DEVSPACE_PUBLIC_BASE_URL.
if [ -n "${DEVSPACE_ISOLATION_PUBLIC_BASE_URL:-}" ]; then
    export DEVSPACE_PUBLIC_BASE_URL="$DEVSPACE_ISOLATION_PUBLIC_BASE_URL"
fi

exec "$@"
