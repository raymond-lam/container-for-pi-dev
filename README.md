# Pi Coding Agent — Docker Sandbox

A thin Docker wrapper for the [Pi Coding Agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent) that keeps your host machine clean while preserving a seamless development experience.

The companion `pi` script builds the image, injects your API key, and forwards just enough host state (workspace, Git identity, GitHub CLI auth) so that the agent behaves as if it were running natively — without requiring Node.js, npm, or Pi itself on your host.

---

## Prerequisites

- **Docker**
- **OpenRouter API key**
- **macOS** (the wrapper reads the API key from your login keychain by default)
- `git` (optional — used to forward your Git identity and SSH signing configuration)

> **Linux users:** see the [API key setup](#linux-api-key-setup) section below.

---

## Quick start

1. Clone this repository.
2. Make sure you have an OpenRouter API key stored in macOS Keychain with service `openrouter.ai` and account `api-key`.
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
| Current working directory | `/workspace` | Read/write — your project files |
| `~/.pi/agent` | `/root/.pi/agent` | Persistent agent state across runs |
| OpenRouter API key | `OPENROUTER_API_KEY` env var | Fetched securely from macOS Keychain |
| Git `user.name` / `user.email` | `/root/.gitconfig` | Rewritten with container-native paths |
| Git SSH signing key | `/root/.ssh/git-signing.pub` | Only the specific key file is shared |
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

## Linux API key setup

The default wrapper reads from macOS Keychain via `security`. On Linux, edit the relevant lines in the `pi` script:

```bash
# Replace this macOS-specific line:
OPENROUTER_API_KEY="$(security find-generic-password -s openrouter.ai -a api-key -w)"

# With an environment variable or your preferred secret manager:
OPENROUTER_API_KEY="${OPENROUTER_API_KEY:-}"
```

---

## Files

| File | Purpose |
|---|---|
| `pi` | Bash wrapper — the only file you need to invoke |
| `Containerfile` | OCI image definition (Node.js 24 + Pi + `gh` CLI) |
| `.dockerignore` | Excludes `.git`, env files, and editor debris from the build context |

---

## Security notes

- The container runs as `root`. This is acceptable for a local sandbox, but do not use this image in production or multi-tenant environments as-is.
- No host SSH agent socket is forwarded — only the Git signing public key and the `gh` token store are shared.
- The `.dockerignore` ensures that `.env` files and your local `.git` directory never enter the Docker build context.

---

## License

This project is licensed under the Apache License, Version 2.0.  
Copyright 2026 Raymond Lam. See [LICENSE](LICENSE) and [NOTICE](NOTICE) for details.

The Pi Coding Agent itself is published under its own license by Earendil Works.
