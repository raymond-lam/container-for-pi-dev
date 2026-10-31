# Copyright 2026 Raymond Lam
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Pi Coding Agent — Container Image
#
# This Containerfile builds the runtime for the pi coding agent. It is intended
# to be built and run via the companion `pi` wrapper script, though you can
# also build it directly if you prefer.
#
# The image is based on node:24-bookworm-slim and adds the tools pi expects
# to find in PATH (bash, git, ripgrep) plus the GitHub CLI (`gh`) so that
# authenticated `gh` operations work inside the container.

FROM node:24-bookworm-slim

# Install core tools.
#   • bash        – required by some pi internals
#   • ca-certificates – HTTPS support for curl / npm
#   • curl        – used to fetch the GitHub CLI signing key
#   • git         – version control
#   • gnupg       – sometimes required by apt keyring operations
#   • openssh-client – ssh-keygen for SSH commit signing
#   • pre-commit  – runs repositories' pre-commit hooks (pulls in Python)
#   • ripgrep     – fast search, used by pi
#   • socat       – bridges the host SSH agent TCP proxy to a Unix socket
#   • tini        – minimal init that reaps zombies and forwards signals
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash=5.2.15-2+b13 \
    ca-certificates=20230311+deb12u1 \
    curl=7.88.1-10+deb12u15 \
    git=1:2.39.5-0+deb12u3 \
    gnupg=2.2.40-1.1+deb12u2 \
    openssh-client=1:9.2p1-2+deb12u10 \
    pre-commit=3.0.4-1 \
    ripgrep=13.0.0-4+b2 \
    socat=1.7.4.4-2 \
    tini=0.19.0-1+b3 \
  && rm -rf /var/lib/apt/lists/*

# Install the GitHub CLI (gh) from the official GitHub APT repository.
# This makes `gh` available inside the container so that the wrapper script
# can forward your host authentication via ~/.config/gh.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
  && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
  && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    > /etc/apt/sources.list.d/github-cli.list \
  && apt-get update \
  && apt-get install -y --no-install-recommends gh=2.103.2 \
  && rm -rf /var/lib/apt/lists/*

# Install the pi coding agent globally. --ignore-scripts is used because
# the package does not require any post-install lifecycle scripts.
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@1.4.0

# Run as an unprivileged user whose UID/GID can be aligned with the host
# (the wrapper passes the invoking user's IDs as build args). Matching the
# host IDs keeps bind-mounted project and agent state files writable on
# native Linux, where ownership is enforced.
ARG APP_UID=1000
ARG APP_GID=1000

# The base image ships a `node` user at UID/GID 1000. Remove it so the pi
# user can take those IDs without ambiguity, then create pi. -o allows a
# non-unique GID, since host GIDs (e.g. staff=20 on macOS) can collide with
# Debian's system groups.
RUN userdel -r node 2>/dev/null || true \
  && groupdel node 2>/dev/null || true \
  && groupadd -o --gid "${APP_GID}" pi \
  && useradd -o --uid "${APP_UID}" --gid "${APP_GID}" \
       --create-home --shell /bin/bash pi \
  && mkdir -p /home/pi/.config/git /home/pi/.config/gh /home/pi/.ssh /run/pi \
  && chown -R "${APP_UID}:${APP_GID}" /home/pi /run/pi \
  && chmod 700 /home/pi/.ssh

# The entrypoint optionally starts a socat bridge so the host SSH agent
# proxy is available to ssh-keygen at a normal Unix socket path. It then execs
# tini so background processes are reaped and signals are forwarded.
COPY entrypoint /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

# Run unprivileged from here on. HOME is set explicitly so tools that do not
# consult the passwd database still resolve the right config locations.
ENV HOME=/home/pi
USER pi

WORKDIR /home/pi
ENTRYPOINT ["/usr/local/bin/entrypoint"]
CMD ["pi"]
