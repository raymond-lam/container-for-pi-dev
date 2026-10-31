# Agent Context: Pi Coding Agent — Docker Sandbox

## Project Overview

This repository is a **Docker sandbox wrapper** for the [Pi Coding Agent](https://www.npmjs.com/package/@earendil-works/pi-coding-agent). It provides a clean, isolated runtime environment that keeps Node.js, npm, and Pi itself off the host machine.

The wrapper (`pi`) builds a container image, injects sensitive credentials (API keys, GitHub tokens) securely from the host, and forwards just enough host state (project files, Git identity, `gh` config) so the agent behaves natively.

## Architecture

```
┌─────────────────┐     ┌──────────────────────────┐
│   Host machine  │────▶│  Docker container        │
│  (macOS/Linux)  │     │  (node:24-bookworm-slim) │
└─────────────────┘     └──────────────────────────┘
         │                         │
    pi script                 Pi agent binary
    (bash)                    (npm global install)
```

### Key Files

| File | Language | Purpose |
|------|----------|---------|
| `pi` | Bash | The wrapper script — builds image, sets up mounts/env, launches container. Primary user-facing interface, and bridge-aware for the `pi0.pi-vscode` extension (same-path mounts, bridge URL + token forwarding, clean stdout for RPC mode). |
| `Containerfile` | Dockerfile | OCI image definition based on `node:24-bookworm-slim` (see README Files table for the full package list). Must remain secret-free. `socat` (SSH-agent bridging) and `tini` (init/zombie reaping) are load-bearing: the SSH signing proxy and signal handling depend on them. |
| `entrypoint` | Shell | Container entrypoint; optionally bridges the host SSH agent proxy. |
| `.dockerignore` | — | Excludes `.git`, env files, credentials, and editor debris from the build context. |
| `README.md` | Markdown | User-facing documentation, including the full Files table. Keep in sync with script behaviour. |
| `LICENSE` | — | Apache 2.0 |
| `NOTICE` | — | Attribution notice; referenced from the README License section. |

## Conventions & Design Principles

### Security-first credential handling
- **Never** mount the entire `~/.ssh` directory into the container.
- Private SSH keys are never mounted. Git signing uses the forwarded host SSH agent so `ssh-keygen` can sign with the key's private half.
- **Never** mount `~/.gitconfig` verbatim — it contains host-specific absolute paths.
- The script reads only the specific values it needs (`user.name`, `user.email`, `user.signingkey`, `gpg.ssh.allowedSignersFile`) and rewrites them with container-native paths.
- API keys are fetched at runtime and injected as env vars; they are never baked into the image.
- `gh` OAuth token is obtained via `gh auth token` and passed as `GH_TOKEN` — the container never accesses the host keychain directly.
- `gh` forwarding is `config.yml`-only and read-only; `hosts.yml` is deliberately never mounted. Do not "fix" this perceived gap by adding `hosts.yml`.

### Minimal, explicit forwarding
- Each mount and env var is justified. If something isn't needed, don't forward it.
- TTY and stdin detection is deliberate: `-i` when input is readable, `-t` only when both stdout and stderr are terminals. This preserves colours, progress bars, and interactive prompts.

### Idempotent builds
- The image is rebuilt on every invocation, but Docker layer caching makes this near-instant when nothing changed. This avoids stale images without complicating the script with manual hash checks.

## Development Workflow

### Testing changes to the wrapper script
```bash
# From the repo root:
./pi --help
```

### Testing changes to the image
```bash
# Force a rebuild by editing Containerfile or using --no-cache:
docker build -f Containerfile -t localhost/pi-sandbox --no-cache .
```

### Lint/check the bash script
```bash
bash -n pi          # syntax check
shellcheck pi       # if available — strongly recommended
```

## Common Tasks

### Adding a new forwarded resource
1. Decide if it's sensitive. If yes, prefer env var injection over volume mounts.
2. If mounting a file, mount only the specific file, not a parent directory containing other credentials.
3. Add the logic to the `pi` script in its own numbered section (follow the existing pattern).
4. Add a row to the "What gets forwarded" table in `README.md`.
5. Test interactively and non-interactively (`echo "prompt" | ./pi`).

### Updating dependencies
- **Pi agent version:** bump the version in `Containerfile` (`npm install -g @earendil-works/pi-coding-agent@X.Y.Z`).
- **System packages:** pin Debian versions in the `apt-get install` line to keep builds reproducible. This includes `pre-commit`, which pulls in Python; bump its pin when you need a newer pre-commit.
- **GitHub CLI:** update the pinned `gh=` version in `Containerfile` to the desired version.

### Supporting additional OSes
- The script already reads `OPENROUTER_API_KEY` from the environment first and only falls back to the macOS Keychain when `security` exists. The remaining gap for Linux/Windows is alternate secret stores (pass, 1Password, Windows Credential Manager) and untested Windows specifics.
- Keep the existing macOS path as the default to avoid breaking existing users.

## Things to Be Careful About

- **Do not** change `WORKDIR /home/pi`, `ENTRYPOINT ["/usr/local/bin/entrypoint"]`, or `CMD ["pi"]` in `Containerfile` without updating the wrapper script assumptions. The wrapper always overrides the working directory with `-w "$PWD"`.
- **Do not** bake secrets into the image. The `Containerfile` must remain secret-free.
- The `teardown` function is the single place that stops the proxy/agent PIDs, removes the sandbox container, and deletes the temp dirs. It takes a flat argument list: PIDs to stop, then `container:<name>` tokens removed with `docker rm -f`, then a `--` separator, then paths to delete. Background processes and temp dirs are registered by appending to `TEARDOWN_PIDS`, `TEARDOWN_CONTAINERS`, and `TEARDOWN_DIRS` where they are created — never build a hand-written list at a call site. Both the `trap cleanup EXIT` (pre-launch failures) and the cleaner process (normal exit after `exec`) call it, so add new cleanup work there, not in either caller. The cleaner runs it from a fresh bash via `export -f`, which is why it must be invoked with `"$BASH"` and not `bash`: function import between different bash versions is unreliable.
- Note that the cleaner receives a **snapshot** of the teardown registries taken when it is spawned, and `TEARDOWN_CONTAINERS` is only appended *after* the FIFO writer is opened (`exec 9>`). On the normal exit path the cleaner therefore never removes the container — removal relies entirely on `docker run --rm`. Keep that in mind if you ever drop `--rm` or rely on `container:` tokens for the normal path.
- The script `exec`s docker as its last action. Cleanup therefore cannot rely on the EXIT trap alone: it is handed to a detached cleaner that blocks reading a named FIFO whose write end docker inherits, so EOF fires exactly when docker exits. Two rules for that handoff: the pipe must be a **named FIFO opened with a plain redirection** (`exec 9> path`), never process substitution — bash marks process-substitution descriptors close-on-exec (macOS `/bin/bash` 3.2 does this), which makes the cleaner fire immediately and delete the git config before docker can mount it. And the writer must be opened only *after* the cleaner starts, or the `open()` blocks. Corollary: start every background process **before** `exec 9>`, because any child alive at that point inherits the write end and holds cleanup off until it exits.
- The script uses `set -euo pipefail`. Any new command pipelines must handle undefined variables and exit codes explicitly. Watch out for simple assignments with command substitution of *optional* values: under `set -e`, `X=$(git config --global user.name)` aborts the whole script when the key is unset (exit code 1), even though git identity is documented as optional. The same applies to `GH_TOKEN="$(gh auth token)"` when `gh` is installed but unauthenticated. These optional reads (the git config identity keys, `gh auth token`) are already guarded with `|| true`; new optional-value assignments must follow the same pattern.
- The VS Code bridge URL fallback rewrite applies both `${URL/127.0.0.1/$HOST_ALIAS}` and `${URL/localhost/$HOST_ALIAS}` sequentially, so a URL containing both patterns is fully rewritten. The limitation is that each pattern replaces only its **first** occurrence: a URL containing two occurrences of the same pattern gets only partially rewritten. The socat relay path on Linux handles loopback URLs properly instead.
- Temp files that are bind-mounted into the container must live on a path Docker can see. On macOS that excludes `$TMPDIR` (`/var/folders/...`), which Docker Desktop does not share, so the git config temp dir is created under `$HOME/.pi/tmp` on every platform.
- `security find-generic-password` is a macOS-specific tool. Guard it or provide fallbacks when adding cross-platform support.
- The SSH-agent signing proxy exposes an **unauthenticated** signature oracle: keep the bind address as narrow as possible and do not widen it.
- Docker on macOS can be slow for volume I/O. The `.dockerignore` is intentionally minimal to keep the build context small.
- Runtime tunables are read from env vars with safe defaults, documented in the README Configuration section. Follow this pattern when adding a new tunable: `"${PI_X:-default}"`.
- The script refuses to run as root (UID/GID 0): keep that refusal guard if you touch the launch path.
- When `GH_TOKEN` is available, the generated gitconfig also appends a `[credential "https://github.com"]` block using the `gh` credential helper (with an empty helper line first to reset inherited helpers). Keep this in mind when editing the gitconfig generation: it depends on `GH_TOKEN`, not on the git identity block.
- The wrapper appends a container-awareness notice via `--append-system-prompt` and forwards the content of `~/.pi/agent/APPEND_SYSTEM.md`. The flag **replaces** Pi's own discovery of `<agent-dir>/APPEND_SYSTEM.md` and `.pi/APPEND_SYSTEM.md` — flag this caveat for anyone editing the launch line.

## Release Checklist

1. Update pinned versions in `Containerfile` (the README does not pin versions).
2. Run `./pi --help` to verify the image builds and Pi launches.
3. Verify Git identity is correctly forwarded: `./pi` then inside the container run `git config --list`.
4. Verify `gh` works: `./pi` then inside run `gh auth status`.

There are no tagged releases; do not tag.
