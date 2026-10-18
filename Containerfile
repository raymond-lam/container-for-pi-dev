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
#   • ripgrep     – fast search, used by pi
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
    bash=5.2.15-2+b13 \
    ca-certificates=20250419~deb12u1 \
    curl=7.88.1-10+deb12u15 \
    git=1:2.39.5-0+deb12u3 \
    gnupg=2.2.40-1.1+deb12u2 \
    ripgrep=13.0.0-4+b2 \
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
  && apt-get install -y --no-install-recommends gh=2.102.0 \
  && rm -rf /var/lib/apt/lists/*

# Install the pi coding agent globally. --ignore-scripts is used because
# the package does not require any post-install lifecycle scripts.
RUN npm install -g --ignore-scripts @earendil-works/pi-coding-agent@1.3.0

WORKDIR /workspace
ENTRYPOINT ["pi"]
