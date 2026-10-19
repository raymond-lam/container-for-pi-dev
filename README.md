# Pi Coding Agent — Docker Sandbox

A thin Docker wrapper for the [Pi Coding Agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) that keeps your host machine clean while preserving a seamless development experience.

The companion `pi` script builds the image, injects your API key, and forwards just enough host state (workspace, Git identity, GitHub CLI auth) so that the agent behaves as if it were running natively — without requiring Node.js, npm, or Pi itself on your host.

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
   ln -s "$(realpath pi-sandbox/pi)" ~/bin/pi
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
| Git `user.name` / `user.email` | `/root/.gitconfig` | Rewritten with container-native paths |
| Git SSH signing public key | `/root/.ssh/git-signing.pub` | Only the specific public key file is shared; a private key path is rejected |
| Host SSH agent | `SSH_AUTH_SOCK` env var | Forwarded via a short-lived `socat` TCP proxy so `ssh-keygen` can sign; private keys are never mounted |
| Git `allowed_signers` | `/root/.config/git/allowed_signers` | For SSH signature verification |
| `gh` config (`~/.config/gh`) | `/root/.config/gh` | Read-only settings, aliases, etc. |
| `gh` OAuth token | `GH_TOKEN` env var | Retrieved from host keychain via `gh auth token` and injected so `gh` works without a container login |

The wrapper intentionally **does not** mount your entire `~/.ssh` or `~/.gitconfig` verbatim, avoiding host-specific absolute paths and unnecessary credential exposure.

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

## VS Code extension (`pi0.pi-vscode`)

The `pi` wrapper works with the [Pi Coding Agent VS Code extension](https://marketplace.visualstudio.com/items?itemName=pi0.pi-vscode). Point the extension at it:

1. Make sure the script is executable and lives at a stable path:

   ```bash
   chmod +x pi
   ```

2. In VS Code settings, set **`pi-vscode.path`** to the absolute path of the script, e.g. `/Users/you/pi-sandbox/pi`.

3. Run **Pi: Open** (`Ctrl+Alt+3`), or use the `@pi` chat participant.

When launched by the extension, the wrapper additionally handles the bridge and its path assumptions:

- **Same-path workspace** — the project is mounted at its host absolute path (instead of `/workspace`), so file paths returned by the VS Code bridge resolve inside the container.
- **Extension mount** — the installed `pi0.pi-vscode` extension directory is discovered under the common VS Code extension roots and mounted read-only at the same host path.
- **Bridge URL rewrite** — `PI_VSCODE_BRIDGE_URL` is rewritten to the wrapper's shared host alias so the container can reach the extension's localhost bridge. The bridge token and terminal ID are forwarded too.
- **Session continuity** — `~/.pi/agent` is mounted at its host path and advertised via `PI_CODING_AGENT_DIR`, so the extension can track and restore terminal sessions across window reloads.
- **Clean stdio** — build output goes to stderr, keeping `pi --mode rpc` stdout parseable for the `@pi` chat participant.

> **Requirements and limits**
>
> - The VS Code extension host must run on the same machine (and network namespace) as Docker. Remote SSH / Dev Container setups only work if the extension and Docker both run on that remote host and the bridge is reachable.
> - The wrapper uses one host address for both the bridge and SSH agent: `host.docker.internal` on Docker Desktop/Podman, and `127.0.0.1` with `--network=host` on native Linux.
> - Extension bridge tools see the same file paths as the host, which is why the workspace is mounted at its host path rather than `/workspace`.
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
| `Containerfile` | OCI image definition (Node.js 24 + Pi + `gh` CLI) |
| `entrypoint` | Container entrypoint; optionally bridges the host SSH agent proxy |
| `.dockerignore` | Excludes `.git`, env files, and editor debris from the build context |

---

## Security notes

- The container runs as `root`. This is acceptable for a local sandbox, but do not use this image in production or multi-tenant environments as-is.
- The host SSH agent socket is forwarded so `ssh-keygen` can produce signatures without mounting private keys. Unix sockets cannot cross the Docker Desktop/Podman VM boundary, so the wrapper uses a short-lived `socat` TCP proxy and recreates the socket inside the container. On native Linux the proxy binds to loopback under host networking; on VM-based runtimes it binds all interfaces for the duration of the run. The wrapper refuses to mount a private key even if `user.signingkey` points at one. The agent can sign with any key it holds, so only keep the keys you intend to use loaded. On macOS, make sure the signing key is available via `ssh-add --apple-use-keychain <key>`.
- The `.dockerignore` ensures that `.env` files and your local `.git` directory never enter the Docker build context.

---

## License

This project is licensed under the Apache License, Version 2.0.  
Copyright 2026 Raymond Lam. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

The Pi Coding Agent itself is published under its own license by Earendil Works.
