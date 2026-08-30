# Runs the real DevSpace MCP server (github.com/Waishnav/devspace,
# @waishnav/devspace on npm, MIT licensed) inside the isolation posture
# ADR 0015 requires. See docs/specs/devspace-isolation-container-framework.md.
#
# DevSpace itself needs Node >=22.19 <27, npm, git, and a Bash-compatible
# shell (its own README, Platform Support). The package is installed at BUILD
# time, not at container startup -- this means the running container needs no
# runtime egress to npm at all; only `docker build` touches the network.

FROM node:22-bookworm-slim

RUN apt-get update \
    && apt-get install -y --no-install-recommends git bash ca-certificates curl \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @waishnav/devspace \
    && useradd --create-home --uid 10001 --shell /bin/bash devspace

ENV HOME=/home/devspace

# The whole home directory becomes a volume mount point in
# docker-compose.yml -- DevSpace writes ~/.devspace/{auth.json,worktrees,...}
# under $HOME by default (v1.0.8 has no DEVSPACE_CONFIG_DIR; see
# docker-entrypoint.sh). A named volume over all of $HOME still exposes no
# host path (unlike the repo bind-mounts under /repos), so this doesn't
# widen this container's host-path exposure; it just needs to exist with
# the right ownership before Docker seeds a new volume from it.
RUN chown -R 10001:10001 /home/devspace

COPY --chown=10001:10001 docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

WORKDIR /repos
RUN chown 10001:10001 /repos

USER 10001:10001

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
CMD ["devspace", "serve"]
