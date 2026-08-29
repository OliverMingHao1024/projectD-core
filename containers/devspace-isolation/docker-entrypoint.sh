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
export DEVSPACE_ALLOWED_ROOTS="/workspace"

# The bind-mounted repo is owned by whatever UID/GID the host filesystem
# reports (via Docker Desktop's Windows/WSL2 bind-mount translation), which
# essentially never matches this container's UID 10001. git's dubious-
# ownership protection then refuses every git operation inside /workspace
# with "detected dubious ownership" -- confirmed by testing (ChatGPT's own
# `bash` tool call failed with exactly this error on a fresh
# open_workspace). This does not weaken the isolation posture: it only
# tells git to trust the one bind-mounted path this container was already
# explicitly given, not any other directory.
git config --global --add safe.directory /workspace

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
