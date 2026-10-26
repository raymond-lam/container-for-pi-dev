# Pi Coding Agent — Docker Sandbox

A thin Docker wrapper for the [Pi Coding Agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) that keeps your host machine clean while preserving a seamless development experience.

The companion `pi` script builds the image, injects your API key, and forwards just enough host state (project files, Git identity, GitHub CLI auth) so that the agent behaves as if it were running natively — without requiring Node.js, npm, or Pi itself on your host.

The same wrapper is bridge-aware and can also be used with the [Pi Coding Agent VS Code extension](https://marketplace.visualstudio.com/items?itemName=pi0.pi-vscode) (`pi0.pi-vscode`).

---

## Prerequisites

- **Docker**
- **socat** on the host (`brew install socat` or `apt install socat`) for SSH commit signing
- **OpenRouter API key** — set `OPENROUTER_API_KEY`, or store it in the macOS Keychain
- **Linux or macOS**
- `git` (optional — used to forward your Git identity and SSH signing configuration)

> See [API key setup](#api-key-setup) if you are not on macOS.

---

## Quick start

1. Clone this repository.
2. Provide an OpenRouter API key: either `export OPENROUTER_API_KEY=...`, or on macOS store it in Keychain with service `openrouter.ai` and account `api-key`.
3. Symlink the wrapper into a directory on your `PATH` (e.g. `~/bin`) so you can invoke it from anywhere:

   ```bash
   ln -s "$(realpath /path/to/cloned-repo/pi)" ~/bin/pi
   ```

   Then run the agent from any project directory:

   ```bash
   pi
   ```

The first invocation builds the image; subsequent runs are instant thanks to Docker's layer cache.

---

## What gets forwarded

| Host resource | Container path | Notes |
|---|---|---|
| Current working directory | Same as host | Read/write — your project files |
| `~/.pi/agent` | Same as host | Persistent agent state across runs |
| OpenRouter API key | `OPENROUTER_API_KEY` env var | From the environment, or fetched from macOS Keychain |
| Git `user.name` / `user.email` | `/home/pi/.gitconfig` | Rewritten with container-native paths. The generated config also explicitly sets `commit.gpgsign`/`tag.gpgsign` (`false` when signing is unavailable) and, when `GH_TOKEN` is injected, a `gh` credential helper for GitHub HTTPS auth |
| Git SSH signing public key | `/home/pi/.ssh/git-signing.pub` | Only the configured public key file is mounted; a `user.signingkey` that points at a private key is refused rather than mounted. The key pair is verified by fingerprint before signing is enabled |
| Dedicated SSH signing agent | proxy → ephemeral agent socket | A fresh `ssh-agent` holding only the git signing key is started on the host and proxied via a short-lived `socat` proxy; your personal SSH agent and all private keys stay on the host and are never passed to the container |
| Git `allowed_signers` | `/home/pi/.config/git/allowed_signers` | For SSH signature verification |
| `gh` config (`~/.config/gh/config.yml`) | `/home/pi/.config/gh/config.yml` | Read-only settings and aliases. `hosts.yml` is deliberately not mounted because it can contain plaintext OAuth tokens |
| `gh` OAuth token | `GH_TOKEN` env var | Retrieved from host keychain via `gh auth token` and injected so `gh` works without a container login; git uses it for GitHub HTTPS auth via the `gh` credential helper |

The wrapper intentionally **does not** mount your entire `~/.ssh` or `~/.gitconfig` verbatim, avoiding host-specific absolute paths and unnecessary credential exposure.

### Container awareness

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

The `pi` script detects TTY and stdin state automatically, so interactive prompts, colours, and progress bars work as expected.

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

The script refuses to run as root (host UID/GID 0); the container user mirrors your host UID/GID via build args so bind-mounted files stay writable and owned by you.

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
- **Session continuity** — `~/.pi/agent` is mounted at its host path and advertised via `PI_CODING_AGENT_DIR`, so the extension can track and restore terminal sessions across window reloads.
- **Clean stdio** — build output goes to stderr, keeping `pi --mode rpc` stdout parseable for the `@pi` chat participant.

> **Requirements and limits**
>
> - The VS Code extension host must run on the same machine (and network namespace) as Docker. Remote SSH / Dev Container setups only work if the extension and Docker both run on that remote host and the bridge is reachable.
> - The wrapper uses one host address for both the bridge and SSH agent: `host.docker.internal`. On Linux it is mapped to the Docker bridge gateway via `--add-host=host.docker.internal:host-gateway`; Docker Desktop provides it natively, while Podman may need equivalent configuration. Host networking is not used.
> - Extension bridge tools see the same file paths as the host, which is why the project is mounted at its host path.
> - The extension's **Upgrade Pi and Packages** command upgrades the host Pi, not the Pi installed in the container image. Bump the version in `Containerfile` and rebuild instead.

---

## API key setup

The wrapper uses `OPENROUTER_API_KEY` when it is set, and otherwise reads it from the macOS Keychain via `security`. On Linux (or in CI), export it or load it from your secret manager:

```bash
export OPENROUTER_API_KEY=...
```

---

## Files

| File | Purpose |
|---|---|
| `pi` | Bash wrapper — the main entry point, also bridge-aware for `pi0.pi-vscode` |
| `Containerfile` | OCI image definition (Node.js 24 + Pi + `gh` CLI). The Pi version is pinned here (`@earendil-works/pi-coding-agent@1.4.0` at time of writing) — bump it and rebuild to upgrade |
| `entrypoint` | Container entrypoint; optionally bridges the host SSH agent proxy |
| `.dockerignore` | Excludes `.git`, env files, common credential files, and editor debris from the build context |
| `NOTICE` | Attribution notice (see License) |

---

## Security notes

- The container runs as an unprivileged user (`pi`). The wrapper passes your host UID/GID as build args so bind-mounted files keep their ownership and stay writable on native Linux. UID/GID 0 is rejected. The container also drops all capabilities, enables `no-new-privileges`, and applies CPU, memory, PID, shared-memory, and file-descriptor limits. The memory-plus-swap limit is pinned to `PI_MEMORY`; if the container reaches it, the kernel may OOM-kill a process rather than letting it consume extra swap. This is still a local sandbox, not a hardened multi-tenant runtime.
- For SSH commit signing, the wrapper starts a **fresh, isolated `ssh-agent` on the host** and loads only your git signing key into it — never your personal agent or other identities. It verifies the key pair by fingerprint first (locating the private key by content, not by filename), then shows the container a signature oracle via a short-lived `socat` TCP proxy. The private key itself is never mounted into the container, so a compromised agent can only request signatures with that one key. Independently, the configured `user.signingkey` *path* is the file that gets mounted; if it points at a private key, signing is refused rather than that file being mounted into the sandbox. Unix sockets cannot cross the Docker Desktop/Podman VM boundary, which is why the wrapper proxies the ephemeral agent socket. On Linux the container uses the default Docker network plus `host.docker.internal` (via `host-gateway`) rather than host networking, and the proxy binds to the Docker bridge gateway. On macOS it binds to host loopback, which Docker Desktop forwards via `host.docker.internal`; it is never bound to every interface. If the Docker bridge gateway cannot be determined on Linux, signing is disabled rather than exposing the proxy broadly. If the key pair cannot be confirmed or the agent cannot be started, signing is disabled with a warning rather than failing at commit time.
- The SSH-agent signing proxy is an unauthenticated signature oracle bound to host loopback (macOS) or the Docker bridge gateway (Linux): anything that can reach that address can request signatures with the one loaded signing key. This is a deliberate trade-off — the blast radius is limited to a single, dedicated key — but it is why the proxy is never bound to all interfaces.
- The `.dockerignore` keeps `.git`, `.env` files, common credential files, and editor debris out of the Docker build context. This reduces accidental disclosure to the Docker daemon/builder; it is not a substitute for keeping secrets outside the repository.

---

## License

This project is licensed under the Apache License, Version 2.0.  
Copyright 2026 Raymond Lam. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

The Pi Coding Agent itself is published under its own license by Earendil Works.
