# Docker Sandboxes (sbx)

Docker Sandboxes is Docker's system for running AI coding agents in isolated microVM sandboxes. Each sandbox gets its own Docker daemon, filesystem, and network — the agent can build containers, install packages, and modify files without touching the host system.

Official docs: https://docs.docker.com/ai/sandboxes/

---

## Core concept

```
sbx run claude [PATH...] [-- AGENT_ARGS...]
```

- Creates a sandbox (or reuses an existing one by name) and runs an agent inside it
- The sandbox is a microVM with its own Docker daemon — full isolation from the host
- Git credentials are injected transparently by the sbx proxy — no `gh auth login` needed inside the sandbox
- `gh auth status` shows "not logged in" inside the sandbox; this is expected and does not break git operations

---

## CLI reference

### `sbx run`

```
sbx run [flags] SANDBOX | AGENT [PATH...] [-- AGENT_ARGS...]
```

| Flag | Description |
|---|---|
| `--name string` | Sandbox name (default: `<agent>-<workdir>`). Reuses existing sandbox if name matches. |
| `--branch string` | Create a Git worktree on the given branch (`auto` to auto-generate). CWD inside sandbox becomes the worktree. |
| `--template string` | Base container image (default: agent-specific image) |
| `--kit strings` | Kit to apply (repeatable). Accepts local path, ZIP, OCI ref, or `git+https://...` |
| `--profile string` | Governance profile |
| `--cpus int` | CPU allocation (0 = auto: N-1 host CPUs, min 1) |
| `-m, --memory string` | Memory limit e.g. `8g` (default: 50% of host, max 32 GiB) |

Available agents: `claude`, `codex`, `copilot`, `cursor`, `docker-agent`, `droid`, `gemini`, `kiro`, `opencode`, `shell`

Examples:
```bash
sbx run claude                                 # Claude in current directory
sbx run claude . ~/docs:ro                     # with extra read-only mount
sbx run claude --name my-sandbox               # named, reusable sandbox
sbx run existing-sandbox                       # attach to existing sandbox
sbx run claude --kit ./my-kit/ --kit ./other/  # apply kits
sbx run claude -- --continue                   # pass args to agent
```

### Ports

```bash
sbx ports <sandbox-name> --publish 8080:8080/tcp
sbx ports <sandbox-name>                          # list published ports
sbx ports <sandbox-name> --unpublish 8080:8080/tcp
```

Services inside the sandbox must bind to `0.0.0.0` (not `127.0.0.1`) to be reachable.
Supported protocol suffixes: `tcp` (default, dual-stack), `tcp4`, `tcp6`, `udp`, `udp4`, `udp6`.

### Secrets

```bash
sbx secret set <sandbox-name> github -t "$(gh auth token)"   # existing sandbox (immediate)
sbx secret set -g github -t "$(gh auth token)"               # global (applies at creation)
```

The `github` secret injects a GitHub token for HTTPS git operations. The sbx proxy handles this transparently — the secret ensures pushes work even when `gh auth status` shows not logged in.

### Network policy

```bash
sbx policy allow network -g <domain>[,<domain>...]   # allow specific domain globally
sbx policy allow network -g "**"                     # allow all (not on denylist)
sbx policy log                                       # recent connections and block reasons
sbx policy ls                                        # active rules
```

Blocked requests return HTTP 403 with a structured body:
```
Blocked by network policy: domain <host>
  rule:   "<rule-name>" (domain, deny)
  origin: <origin>       # "local policy" | "corporate policy" | "system policy"
  detail: <explanation>
```

Use `origin` to decide the fix: local policy → `sbx policy allow`; corporate/system → contact IT.

### Templates

```bash
sbx run claude --template my-registry/my-image:tag
sbx template load ...    # load a template (exact syntax requires `sbx template --help`)
```

Templates are Docker images used as the sandbox base. Build with a Dockerfile extending the agent base image, push to a registry, then reference with `--template`. Best for heavy, stable components: language toolchains, large system packages — anything you'd rather not reinstall every run.

### Kits

```bash
sbx run claude --kit ./my-kit/           # local directory
sbx run claude --kit ./my-kit.zip        # ZIP archive
sbx run claude --kit ghcr.io/org/kit:1.0 # OCI registry
sbx run claude --kit git+https://...     # Git repo
sbx kit add <sandbox-name> ./my-kit/     # apply to running sandbox
sbx kit validate <path>                  # validate spec.yaml
sbx kit pack <path>                      # create ZIP archive
sbx kit push <path>                      # publish to OCI registry
sbx kit pull <ref>                       # download published kit
```

---

## Customization: Templates vs Kits

| | Template | Kit |
|---|---|---|
| What it is | Docker image | `spec.yaml` + optional `files/` |
| When applied | At sandbox creation (base image) | At runtime, on top of the agent |
| Build step | `docker build` + push to registry | None — declarative YAML |
| Stackable | No (one base image) | Yes — multiple `--kit` flags |
| Apply to running sandbox | No | Yes — `sbx kit add` |
| Best for | Heavy toolchains, large deps | Tools, env vars, network rules, config files, agent memory |
| Status | Stable | Experimental |

Use a **template** when the base environment is heavy and rarely changes. Use a **kit** for lighter customization that varies per project or team — credentials, network policies, tool installs, injected config.

---

## Kits in depth

### Directory structure

```
my-kit/
├── spec.yaml
└── files/
    ├── home/           # → /home/agent/
    └── workspace/      # → the workspace path
```

### spec.yaml format

```yaml
schemaVersion: "1"
kind: mixin          # or: agent
name: my-kit
displayName: My Kit
description: "What this kit does"

commands:
  install:            # runs once at sandbox creation
    - command: "apt-get install -y maven"
      user: "root"
  startup:            # runs on each sandbox start
    - command: ["my-daemon", "--port", "9000"]
      user: "1000"
      background: true
  initFiles:          # write files before install/startup
    - path: /home/agent/.config/tool.conf
      content: |
        setting=value

network:
  allowedDomains:
    - repo.maven.apache.org
    - central.sonatype.com

environment:
  variables:
    MY_VAR: "value"

credentials:
  - name: github
    env: GH_TOKEN       # or: file: /home/agent/.config/gh/token

memory:               # injected into the agent's system context / CLAUDE.md
  - "Always use mvnw if it exists in the project root"
  - "Java home is managed by SDKMAN at ~/.sdkman"

# agent kits only:
agent:
  image: my-registry/my-agent:latest
  entrypoint: ["/usr/local/bin/my-agent"]
```

### Kit kinds

- **Mixin**: extends an existing agent. Stacks with other mixins. Cannot change the base image.
- **Agent**: defines a complete agent — includes an `agent` block with `image` and `entrypoint`. Replaces the default agent image entirely.

### Community kits

https://github.com/docker/sbx-kits-contrib — community-contributed kits including `mise`, `github-ssh`, `git-ssh-sign`, `trivy`, `vale`, and more.

---

## Environment inside the sandbox

- Shell user: `agent` (uid=1000), has `sudo` and `docker` group membership
- Persistent environment: `/etc/sandbox-persistent.sh` — sourced before every bash command via `CLAUDE_ENV_FILE`
- **Never add shell completions to this file** — they break the bash tool (see CLAUDE.md for details)
- Host services reachable at `host.docker.internal` (not `localhost`)
- Worktree sandboxes (`--branch`): CWD is a git worktree at `<repo>/.sbx/<name>`; canonical repo also mounted at `<repo>`

---

## Worktree sandboxes

When created with `--branch`, the sandbox working directory is a Git worktree:
```
<repo>/.sbx/<sandbox-name>/   ← your CWD inside the sandbox
<repo>/                       ← canonical repo, also mounted (different branch!)
```

**The trap**: search tools (`find`, `grep`) may return paths rooted at the canonical repo. Edits to those paths silently land on the wrong branch. Always verify with `git -C <worktree-root> status` after edits.

Quick sanity check at session start:
```bash
echo "PWD:      $PWD"
echo "git root: $(git rev-parse --show-toplevel)"
echo "branch:   $(git branch --show-current)"
git worktree list
```
