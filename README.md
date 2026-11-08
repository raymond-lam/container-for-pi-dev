# Pi Coding Agent — Docker Sandbox

[![License: Apache 2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Platform: macOS | Linux](https://img.shields.io/badge/platform-macOS%20%7C%20Linux-lightgrey.svg)](#prerequisites)
[![Base image](https://img.shields.io/badge/base-node%3A24--bookworm--slim-2496ED.svg)](Containerfile)

<!-- TODO: record a 10-15s demo (asciinema/QuickTime): pi -> image build -> working session,
     save as docs/demo.gif and uncomment: -->
<!-- ![Demo: launching Pi inside the Docker sandbox](docs/demo.gif) -->

**Run the [Pi coding agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) in a disposable Docker container — an isolated, resource-capped AI coding agent on your machine, without Node.js, npm, or Pi installed on your host.**

- 🧱 **No host install** — Pi, Node.js and npm live only in the image. Your host stays clean.
- 🔑 **Credentials injected, never baked in** — API keys arrive as env vars at runtime; `~/.ssh` and `~/.gitconfig` are never mounted verbatim.
- ✍️ **Commits still sign, `gh` still works** — a dedicated SSH signing agent and `GH_TOKEN` are forwarded, so `git commit -S` and `gh pr create` behave normally.
- 🧩 **Bridge-aware for VS Code** — full support for the [`pi0.pi-vscode`](https://marketplace.visualstudio.com/items?itemName=pi0.pi-vscode) extension, including same-path mounts and clean RPC stdio.

> New to Pi? It's a terminal AI coding agent (in the Claude Code / Cursor-CLI family). This repo only changes *where* it runs.

The companion `pi` script builds the image, injects your API key, and forwards just enough host state (project files, Git identity, GitHub CLI auth) so that the agent behaves as if it were running natively.

---

## Quick start

```bash
git clone https://github.com/raymond-lam/container-for-pi-dev.git ~/src/pi-sandbox
mkdir -p ~/bin && ln -s ~/src/pi-sandbox/pi ~/bin/pi   # ~/bin must be on your PATH

export OPENROUTER_API_KEY=...   # or store in macOS Keychain — see API key setup below
cd ~/my-project && pi           # first run builds the image; later runs are instant
```

You should land at a normal Pi prompt inside the container. `docker ps` shows a
`pi-sandbox-*` container while it runs; it's removed on exit.

<details><summary>Not on macOS? / Keychain setup</summary>

On macOS you can store keys in Keychain instead of exporting them: service `openrouter.ai`,
account `api-key` (and optionally `management-key` for the `pi-openrouter` extension). See
[API key setup](#api-key-setup).

</details>

---

## Prerequisites

- **Docker**
- **socat** on the host (`brew install socat` or `apt install socat`) for SSH commit signing on all platforms, and for the VS Code bridge relay on Linux
- **OpenRouter API key** — set `OPENROUTER_API_KEY`, or store it in the macOS Keychain
- **OpenRouter management key** (optional, for the `pi-openrouter` extension) — set `OPENROUTER_MANAGEMENT_KEY`, or store it in the macOS Keychain
- **Linux or macOS**
- `git` (optional — used to forward your Git identity and SSH signing configuration)

> See [API key setup](#api-key-setup) if you are not on macOS.

---

## Why run Pi in a container?

| | Pi on the host | This sandbox |
|---|---|---|
| Host Node.js / npm / Pi install | required | none |
| Agent can write outside your project | yes (your whole home dir) | container filesystem: project + `~/.pi` only; [VS Code bridge is an exception](#vs-code-bridge-permissions) |
| Resource limits (CPU / RAM / PIDs) | no | capped, and tunable |
| SSH keys reachable by the agent | your whole agent | one dedicated signing key, signatures only |
| `gh` auth | your keychain | token env var only; `hosts.yml` never mounted |
| Reproducible toolkit (ripgrep, `gh`, pre-commit, git) | depends on your machine | pinned in `Containerfile` |
| Cost | none | one container per session |

**When not to use it:** single-user local development only. `~/.pi` is mounted read-write
(credentials and extensions are visible to container processes), an OpenRouter key is
required, and the signing proxy is an unauthenticated, loopback-bound signature oracle.
Windows is unsupported outside WSL2.

---

## What gets forwarded

| Host resource | Container path | Notes |
|---|---|---|
| Current working directory | Same as host | Read/write — your project files |
| `~/.pi` (including `~/.pi/agent`) | `/home/pi/.pi` | Read/write, persistent. Includes `agent/auth.json` (provider credentials), settings, extensions, sessions, and caches; all are visible and writable inside the container. Mounting the parent also lets extensions persist sibling files alongside `agent` |
| OpenRouter API key | `OPENROUTER_API_KEY` env var | Required. From the environment, or fetched from macOS Keychain |
| OpenRouter management key | `OPENROUTER_MANAGEMENT_KEY` env var | Optional. Used by `pi-openrouter` for usage/analytics, model sync, and API key management. From the environment, or fetched from macOS Keychain; not forwarded when absent |
| Git `user.name` / `user.email` | `/home/pi/.gitconfig` | Rewritten with container-native paths. The generated config also explicitly sets `commit.gpgsign`/`tag.gpgsign` (`false` when signing is unavailable) and, when `GH_TOKEN` is injected, a `gh` credential helper for GitHub HTTPS auth |
| Git SSH signing public key | `/home/pi/.ssh/git-signing.pub` | Only the configured public key file is mounted; a `user.signingkey` that points at a private key is refused rather than mounted. The key pair is verified by fingerprint before signing is enabled |
| Dedicated SSH signing agent | proxy → ephemeral agent socket | A fresh `ssh-agent` holding only the git signing key is started on the host and proxied via a short-lived `socat` proxy; your personal SSH agent and all private keys stay on the host and are never passed to the container |
| Git `allowed_signers` | `/home/pi/.config/git/allowed_signers` | For SSH signature verification |
| `gh` config (`~/.config/gh/config.yml`) | `/home/pi/.config/gh/config.yml` | Read-only settings and aliases. `hosts.yml` is deliberately not mounted because it can contain plaintext OAuth tokens |
| `gh` OAuth token | `GH_TOKEN` env var | Retrieved via `gh auth token` and injected so `gh` works without a container login; git uses it for GitHub HTTPS auth via the `gh` credential helper |
| VS Code bridge (when enabled) | `PI_VSCODE_BRIDGE_URL`, `PI_VSCODE_BRIDGE_TOKEN`, `PI_VSCODE_TERMINAL_ID` env vars | URL rewritten for container reachability. Grants host-side editor capabilities beyond the bind mounts — see [bridge permissions](#vs-code-bridge-permissions) |

The wrapper does not mount `~/.ssh` or `~/.gitconfig` verbatim, but it does mount all of `~/.pi` read-write. Container processes can read and modify Pi's credentials and state there; only use this sandbox with trusted code and extensions.

---

## Container awareness

Pi has no built-in notion of running inside a container, so the wrapper appends a short container notice to Pi's system prompt via a repeatable `--append-system-prompt` argument. It tells the agent that the environment is ephemeral and unprivileged, which host paths exist, how git signing and GitHub auth work, and what resource caps apply.

Caveat: Pi treats a CLI `--append-system-prompt` as a replacement for its own discovery of `<agent-dir>/APPEND_SYSTEM.md` and `.pi/APPEND_SYSTEM.md`. The wrapper therefore forwards a global `~/.pi/agent/APPEND_SYSTEM.md` itself (concatenated ahead of the notice). A project-level `.pi/APPEND_SYSTEM.md` is still not picked up when running through the wrapper.

---

## Usage

Pass any Pi subcommand or flags directly:

```bash
# Start an interactive session
pi

# Run a specific Pi command (examples)
pi --help
pi --model claude-3.5-sonnet
```

The `pi` script detects TTY and stdin state automatically, so interactive prompts, colours, and progress bars work as expected. After the Docker image build, if `caffeinate` is available on `PATH`, the wrapper runs `caffeinate -i` in the background while active to prevent idle sleep. If it is unavailable, the wrapper continues without a sleep assertion. This does not prevent sleep when you close the lid.

The image includes [pre-commit](https://pre-commit.com), so repositories that already use it work inside the sandbox without installing it on the host. If a repository's hook was installed by pre-commit on the host, re-run `pre-commit install` inside the container: the generated hook embeds the absolute path of the Python interpreter that created it. Hook environments are cached under `~/.cache/pre-commit`, which is not mounted, so they are recreated per container session.

---

## Configuration

The wrapper reads optional environment variables with safe defaults:

| Variable | Default | Purpose |
|---|---|---|
| `PI_CPUS` | `2` | Container CPU limit |
| `PI_MEMORY` | `4g` | Container memory and memory-plus-swap limit |
| `PI_SHM_SIZE` | `64m` | `/dev/shm` size; raise for browser-based tests (e.g. `256m`) |
| `PI_PIDS_LIMIT` | `512` | Container PID limit |
| `PI_NOFILE_SOFT` / `PI_NOFILE_HARD` | `4096` / `8192` | File-descriptor ulimit (soft/hard) |
| `PI_SSH_AGENT_PORT` | ephemeral | Fixed port for the SSH signing agent proxy, if you need one |

`PI_MEMORY` is a ceiling, not a reservation. It also sets the total memory-plus-swap limit, so the container may be OOM-killed under memory pressure instead of consuming additional swap; lower it for small Docker hosts or VMs. `PI_PIDS_LIMIT` can be raised for unusually heavy parallel workloads. `PI_SHM_SIZE` keeps Docker's 64 MiB default unless increased; shared-memory use still counts against `PI_MEMORY`.

The script refuses to run as root and mirrors your host UID/GID in the container — see [Security notes](#security-notes) for the rationale.

---

## VS Code extension (`pi0.pi-vscode`)

The `pi` wrapper works with the [Pi Coding Agent VS Code extension](https://marketplace.visualstudio.com/items?itemName=pi0.pi-vscode). Point the extension at it:

1. Make sure the script is executable and lives at a stable path:

   ```bash
   chmod +x pi
   ```

2. In VS Code settings, set **`pi-vscode.path`** to the absolute path of the script, e.g. `/Users/you/pi-sandbox/pi`.

3. Run **Pi: Open** (`Ctrl+Alt+3`), or use the `@pi` chat participant.

When launched by the extension, the wrapper additionally handles the bridge and its path assumptions:

- **Same-path project mount** — the project is mounted at its host absolute path, so file paths returned by the VS Code bridge resolve inside the container.
- **Extension mount** — the installed `pi0.pi-vscode` extension directory is discovered under the common VS Code extension roots and mounted read-only at the same host path.
- **Bridge URL rewrite** — `PI_VSCODE_BRIDGE_URL` is rewritten to the wrapper's shared host alias so the container can reach the extension's localhost bridge. The bridge token and terminal ID are forwarded too.
- **Session continuity** — the host's `~/.pi/agent` is mounted at `/home/pi/.pi/agent` and advertised via `PI_CODING_AGENT_DIR`, so the extension can track and restore terminal sessions across window reloads.
- **Clean stdio** — build output goes to stderr, keeping `pi --mode rpc` stdout parseable for the `@pi` chat participant.

> **Requirements and limits**
>
> - The VS Code extension host must run on the same machine (and network namespace) as Docker. Remote SSH / Dev Container setups only work if the extension and Docker both run on that remote host and the bridge is reachable.
> - The wrapper uses one host address for both the bridge and SSH agent: `host.docker.internal`. On Linux it is mapped to the Docker bridge gateway via `--add-host=host.docker.internal:host-gateway`; Docker Desktop provides it natively, while Podman may need equivalent configuration. Host networking is not used.
> - Extension bridge tools see the same file paths as the host, which is why the project is mounted at its host path.
> - The extension's **Upgrade Pi and Packages** command upgrades the host Pi, not the Pi installed in the container image. Bump the version in `Containerfile` and rebuild instead.

### VS Code bridge permissions

**The VS Code bridge is a host-capability channel, not part of Docker's filesystem sandbox.** The wrapper forwards its URL and authentication token into the container; bridge requests execute in the host-side VS Code extension, with VS Code's access to host files. Docker's bind-mount restrictions do not constrain those operations, including paths outside the mounted project.

In the current upstream implementation, two tools deserve explicit approval:

- `vscode_apply_workspace_edit` applies text replacements through VS Code's `workspace.applyEdit`, changing editor buffers on the host. Auto Save can persist those changes without a separate save-tool call.
- `vscode_save_document` calls VS Code's `document.save()`, writing the host-side buffer to disk, including any existing unsaved changes.

See the upstream [bridge tool documentation](https://github.com/pithings/pi-vscode#bridge-tools-exposed-to-pi) and [handlers](https://github.com/pithings/pi-vscode/blob/main/src/bridge/handlers.ts).

**Recommendation:** install the optional [`@gotgenes/pi-permission-system`](https://www.npmjs.com/package/@gotgenes/pi-permission-system) extension and set both tools to `ask` rather than blanket-allowing them. Merge these entries into the `permission` object in `~/.pi/agent/extensions/pi-permission-system/config.json` (do not replace your other rules):

```json
{
  "permission": {
    "vscode_apply_workspace_edit": "ask",
    "vscode_save_document": "ask"
  }
}
```

Review the target paths and requested changes before approving; inspect dirty buffers before allowing a save. These two rules are not exhaustive: `vscode_format_document`, `vscode_format_range`, and `vscode_execute_code_action` can also mutate host-side documents and should be reviewed for `ask` or `deny` policies. Auto Save is outside the tool-call gate.

Permission prompts are an agent-tool guardrail, **not a hard security boundary**: container processes holding the forwarded bridge token can call the bridge directly, bypassing tool-name permission checks. To avoid granting these host capabilities, use the wrapper from a standalone terminal with `PI_VSCODE_BRIDGE_URL` unset.

---

## API key setup

The wrapper uses `OPENROUTER_API_KEY` when it is set, and otherwise reads it from the macOS Keychain via `security` (service `openrouter.ai`, account `api-key`). This key is **required**. On Linux (or in CI), export it or load it from your secret manager:

```bash
export OPENROUTER_API_KEY=...
```

An OpenRouter **management key** is optional. The `pi-openrouter` extension prefers it for usage/analytics, model sync, and API key management, but works without one. It is resolved the same way: `OPENROUTER_MANAGEMENT_KEY` from the environment first, otherwise the macOS Keychain (service `openrouter.ai management`, account `management-key`; the alternate service `openrouter management` and legacy service `openrouter.ai` are also checked). When neither is set, the key is simply not forwarded to the container:

```bash
export OPENROUTER_MANAGEMENT_KEY=...
```

---

## Files

| File | Purpose |
|---|---|
| `pi` | Bash wrapper — the main entry point, also bridge-aware for `pi0.pi-vscode` |
| `Containerfile` | OCI image definition based on Node.js 24; installs bash, ca-certificates, curl, git, gnupg, openssh-client, pre-commit (with Python), ripgrep, socat, tini, `gh`, and Pi. Package versions are pinned here |
| `entrypoint` | Container entrypoint; optionally bridges the host SSH agent proxy |
| `.github/workflows/ci.yml` | Builds and smoke-tests the image on Linux x64, native Linux ARM64, and Intel macOS (Colima) |
| `.github/renovate.json` | Renovate config for the base image, Debian package pins, `gh`, and Pi |
| `.dockerignore` | Excludes `.git`, env files, common credential files, and editor debris from the build context |
| `LICENSE` | Apache 2.0 license |
| `NOTICE` | Attribution notice (see License) |

---

## CI coverage

On every pull request and push to `main`, CI builds and smoke-tests the image on
`ubuntu-latest` (x64), `ubuntu-24.04-arm` (native ARM64), and `macos-15-intel`
(using Colima, not Docker Desktop). Each host tests the default image, installed
tools, unprivileged user, SSH directory permissions, and entrypoint passthrough.
These checks do not exercise the host wrapper or make provider API calls.

Renovate looks up Debian pins in the Bookworm repositories for amd64; CI checks
whether proposed pins also build on ARM64. Renovate's `deb` datasource currently
[does not support](https://github.com/renovatebot/renovate/issues/44330) the
`.xz`-only Bookworm updates and security indexes. Until it does, security-only
updates may need to be applied manually before they reach the main Bookworm
index. The three-day minimum release age does not apply to Debian packages,
because the datasource does not provide release timestamps. Update the suites
in `.github/renovate.json` when changing the base image suite.

Native Linux ARM64 image coverage is not macOS ARM Docker coverage. Apple
Silicon macOS hosts, including M3 hardware, and Docker Desktop integration
remain untested; the hosted Apple Silicon runners lack the nested virtualization
needed by the Colima setup action.

---

## FAQ

<details><summary>Does it work on Linux without the macOS Keychain?</summary>

Yes — export `OPENROUTER_API_KEY` (and optionally `OPENROUTER_MANAGEMENT_KEY`). The Keychain
path only activates when the `security` CLI exists.

</details>

<details><summary>Podman? WSL2? Windows?</summary>

Podman may need `host.docker.internal` / `host-gateway` configured for the VS Code bridge and
SSH signing; the wrapper does not use host networking. Windows is unsupported outside WSL2.

</details>

<details><summary>Why is <code>~/.pi</code> mounted read-write?</summary>

Pi state (auth credentials, settings, extensions, sessions) must be readable and writable for
the agent to behave natively, and extensions persist sibling files alongside <code>agent</code>.
The trade-off and mitigations are described in <a href="#security-notes">Security notes</a>.

</details>

<details><summary>Why does the SSH signing proxy have no authentication?</summary>

It is an intentional trade-off: the proxy is bound to loopback (macOS) or the Docker bridge
gateway (Linux) only, and forwards a single ephemeral agent that holds only your git signing
key. See <a href="#security-notes">Security notes</a> for the full rationale.

</details>

<details><summary>Can I use a provider other than OpenRouter?</summary>

The wrapper currently requires <code>OPENROUTER_API_KEY</code>. Other providers need a change to
the key-forwarding section of <code>pi</code>.

</details>

<details><summary>Why don't my pre-commit hooks run?</summary>

The image ships <code>pre-commit</code>, but repositories configure hooks per-clone. Re-run
<code>pre-commit install</code> inside the container.

</details>

<details><summary>How do I upgrade Pi?</summary>

Bump the pinned version in <code>Containerfile</code> and rerun. The VS Code extension's
"Upgrade Pi and Packages" command upgrades the host install, not this image.

</details>

---

## Security notes

- The container runs as an unprivileged user (`pi`). The wrapper passes your host UID/GID as build args so bind-mounted files keep their ownership and stay writable on native Linux. UID/GID 0 is rejected. The container also drops all capabilities, enables `no-new-privileges`, and applies CPU, memory, PID, shared-memory, and file-descriptor limits. The memory-plus-swap limit is pinned to `PI_MEMORY`; if the container reaches it, the kernel may OOM-kill a process rather than letting it consume extra swap. This is still a local sandbox, not a hardened multi-tenant runtime.
- The entire `~/.pi` directory is mounted read-write, including `agent/auth.json` provider credentials, settings, and installed extensions. Processes in the container can read or modify this state, and changes persist on the host. Do not run untrusted code or extensions with this mount.
- For SSH commit signing, the wrapper starts a **fresh, isolated `ssh-agent` on the host** and loads only your git signing key into it — never your personal agent or other identities. It locates the private key as the sibling of the `.pub` file, then verifies the key pair by fingerprint, before showing the container a signature oracle via a short-lived `socat` TCP proxy. The private key itself is never mounted into the container, so a compromised agent can only request signatures with that one key. Independently, the configured `user.signingkey` *path* is the file that gets mounted; if it points at a private key, signing is refused rather than that file being mounted into the sandbox. Unix sockets cannot cross the Docker Desktop/Podman VM boundary, which is why the wrapper proxies the ephemeral agent socket. On Linux the container uses the default Docker network plus `host.docker.internal` (via `host-gateway`) rather than host networking, and the proxy binds to the Docker bridge gateway. On macOS it binds to host loopback, which Docker Desktop forwards via `host.docker.internal`; it is never bound to every interface. If the Docker bridge gateway cannot be determined on Linux, signing is disabled rather than exposing the proxy broadly. If the key pair cannot be confirmed or the agent cannot be started, signing is disabled with a warning rather than failing at commit time.
- The SSH-agent signing proxy is an unauthenticated signature oracle bound to host loopback (macOS) or the Docker bridge gateway (Linux): anything that can reach that address can request signatures with the one loaded signing key. This is a deliberate trade-off — the blast radius is limited to a single, dedicated key — but it is why the proxy is never bound to all interfaces.
- When enabled, the [VS Code bridge](#vs-code-bridge-permissions) lets container processes request host-side editor operations beyond the bind mounts. Require approval for mutating bridge tools; disable the bridge if you need its host capabilities excluded.
- The `.dockerignore` keeps `.git`, `.env` files, common credential files, and editor debris out of the Docker build context. This reduces accidental disclosure to the Docker daemon/builder; it is not a substitute for keeping secrets outside the repository.

---

## License

This project is licensed under the Apache License, Version 2.0.  
Copyright 2026 Raymond Lam. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

The Pi Coding Agent itself is published under its own license by Earendil Works.
