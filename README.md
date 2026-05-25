# sbx-claude

Run Claude Code in an [sbx](https://github.com/fleetview/sbx) sandbox.

A thin wrapper around `sbx run claude` that gives each project a **stable sandbox name**, handles GitHub token setup, and prints port-publishing hints.

Compare to [contained-claude](../contained-claude), which builds its own OCI image and manages a socket proxy. `sbx-claude` delegates all of that to sbx — the sandbox is already isolated, already has Docker access, and already injects Git credentials via its proxy.

## Quick start

Requires `sbx` and `gh` (GitHub CLI).

```bash
# Claude in the current directory
./sbx-claude.sh

# Claude in a specific project
./sbx-claude.sh ~/rayvn/rayvn-edge
```

The sandbox is created on first run and **reused on subsequent runs** (same name → same sandbox, accumulated state, warm Maven cache).

## Passing arguments to Claude

```bash
./sbx-claude.sh -- --continue
./sbx-claude.sh -- -p "run the tests"
```

## Options

```bash
./sbx-claude.sh --branch auto           # auto-generate a Git worktree branch
./sbx-claude.sh --branch feature/foo    # worktree on a specific branch
./sbx-claude.sh --mount ~/docs:ro       # mount extra read-only path
./sbx-claude.sh --no-token              # skip GitHub token setup
./sbx-claude.sh --debug                 # launch a shell instead of Claude
```

## Sandbox name

The sandbox is named `claude-<project-folder-name>`, e.g. `claude-rayvn-edge`. This is used consistently so you can manage it from the host:

```bash
# Publish a port
sbx ports claude-rayvn-edge --publish 8080:8080/tcp

# Refresh the GitHub token for an existing sandbox
sbx secret set claude-rayvn-edge github -t "$(gh auth token)"

# List running sandboxes
sbx list
```

## GitHub token

The script calls `sbx secret set` to inject a `github` secret before launching. If the sandbox doesn't exist yet it falls back to `sbx secret set -g` (global, applied at creation).

sbx's proxy also injects Git credentials transparently for HTTPS operations, so `git push` typically works without any extra setup.

## Port publishing

Services inside the sandbox must bind to `0.0.0.0` (not `127.0.0.1`) to be reachable. Publish from the host:

```bash
sbx ports claude-<project> --publish HOST_PORT:SANDBOX_PORT/tcp
```

Common ports: `3000` (Node dev), `4200` (Angular), `5005` (Java debug), `8080` (Spring Boot).

## What sbx provides vs contained-claude

| Feature | contained-claude | sbx-claude |
|---|---|---|
| OCI image build | Custom (Ubuntu 25.10 + SDKMAN) | sbx default agent image |
| Filesystem isolation | Container / bwrap / seatbelt | sbx sandbox |
| Git auth | `GH_TOKEN` env var | sbx proxy (transparent) |
| Container-in-container | Socket proxy with allowlist | Docker available in sandbox |
| Port forwarding | Mapped at `docker run` time | `sbx ports` on the host |
| SSH agent | Forwarded if SSH remotes detected | Not yet handled — use HTTPS remotes |
| `.m2` cache | Mounted from host | Persists inside the sandbox |
| Setup required | `gh`, Podman/Docker | `gh`, `sbx` |

## Known limitations

- **SSH remotes**: SSH agent forwarding is not handled. If your project uses `git@github.com:...` remotes, switch to HTTPS or set up SSH keys inside the sandbox manually.
- **Java/Maven**: The sbx default image ships with Java 21. Maven may need to be installed inside the sandbox (`sudo apt install maven` or via sdkman).
