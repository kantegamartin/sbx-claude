#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./sbx-claude.sh                          # Claude in current directory
#   ./sbx-claude.sh ~/rayvn/rayvn-edge       # Claude in a specific project
#   ./sbx-claude.sh --branch auto            # Claude with an auto-generated Git worktree
#   ./sbx-claude.sh -- --continue            # Resume last Claude session
#   ./sbx-claude.sh -- -p "run the tests"    # Pass a prompt to Claude
#   ./sbx-claude.sh --mount ~/docs:ro        # Add a read-only reference mount
#   ./sbx-claude.sh --debug                  # Launch a shell instead of Claude

# Colors
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# Defaults
PROJECT_FOLDER="$(pwd)"
BRANCH=""
NO_TOKEN=false
DEBUG=false
EXTRA_MOUNTS=()
CLAUDE_ARGS=()

usage() {
    cat <<EOF
${BOLD}sbx-claude${NC} — Run Claude Code in an sbx sandbox

${BOLD}Usage:${NC}
  $(basename "$0") [PROJECT_FOLDER] [OPTIONS] [-- CLAUDE_ARGS]

${BOLD}Options:${NC}
  --branch BRANCH    Create a Git worktree on the given branch (use 'auto' to auto-generate)
  --mount PATH[:ro]  Mount an additional path (repeatable; append :ro for read-only)
  --no-token         Skip GitHub token setup
  --debug            Launch a shell instead of Claude
  -h, --help         Show this help

${BOLD}Examples:${NC}
  $(basename "$0")                           # Claude in current directory
  $(basename "$0") ~/rayvn/rayvn-edge       # Claude in a specific project
  $(basename "$0") --branch auto            # Claude with an auto-generated branch
  $(basename "$0") -- --continue            # Resume the last Claude session
  $(basename "$0") -- -p "run the tests"    # Pass a prompt to Claude
  $(basename "$0") --mount ~/docs:ro        # Add a read-only reference mount

${BOLD}Port publishing (run on host):${NC}
  sbx ports <sandbox-name> --publish 8080:8080/tcp
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)  usage; exit 0 ;;
        --branch)   BRANCH="$2"; shift 2 ;;
        --mount)    EXTRA_MOUNTS+=("$2"); shift 2 ;;
        --no-token) NO_TOKEN=true; shift ;;
        --debug)    DEBUG=true; shift ;;
        --)         shift; CLAUDE_ARGS=("$@"); break ;;
        -*)         echo -e "${RED}Unknown option: $1${NC}" >&2; usage >&2; exit 1 ;;
        *)          PROJECT_FOLDER="$(realpath "$1")"; shift ;;
    esac
done

if [ ! -d "$PROJECT_FOLDER" ]; then
    echo -e "${RED}Error: project folder not found: ${PROJECT_FOLDER}${NC}" >&2
    exit 1
fi

PROJECT_NAME="$(basename "$PROJECT_FOLDER")"
SANDBOX_NAME="claude-$(echo "$PROJECT_NAME" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9' '-' | sed 's/-*$//')"

# GitHub token — try sandbox-specific first (works if sandbox already exists),
# fall back to global (applied at sandbox creation).
if [ "$NO_TOKEN" = false ]; then
    if command -v gh &>/dev/null; then
        GH_TOKEN="$(gh auth token 2>/dev/null || true)"
        if [ -n "$GH_TOKEN" ]; then
            echo -e "${CYAN}Setting GitHub token for '${SANDBOX_NAME}'...${NC}"
            sbx secret set "$SANDBOX_NAME" github -t "$GH_TOKEN" 2>/dev/null || \
                sbx secret set -g github -t "$GH_TOKEN" 2>/dev/null || true
        else
            echo -e "${YELLOW}Warning: gh CLI not authenticated — git push may fail inside the sandbox.${NC}"
            echo -e "${YELLOW}Run 'gh auth login' or use --no-token to suppress this warning.${NC}"
        fi
    fi
fi

# Build sbx run arguments
SBX_ARGS=("--name" "$SANDBOX_NAME")
[ -n "$BRANCH" ] && SBX_ARGS+=("--branch" "$BRANCH")

AGENT="claude"
[ "$DEBUG" = true ] && AGENT="shell"

# Workspaces: project folder first, then any extra mounts
WORKSPACES=("$PROJECT_FOLDER")
for m in "${EXTRA_MOUNTS[@]}"; do
    WORKSPACES+=("$m")
done

echo -e ""
echo -e "${BOLD}Sandbox${NC} : ${GREEN}${SANDBOX_NAME}${NC}"
echo -e "${BOLD}Project${NC} : ${CYAN}${PROJECT_FOLDER}${NC}"
[ -n "$BRANCH" ]      && echo -e "${BOLD}Branch ${NC} : ${CYAN}${BRANCH}${NC}"
[ "$DEBUG" = true ]   && echo -e "${BOLD}Mode   ${NC} : ${YELLOW}shell (debug)${NC}"
[ ${#EXTRA_MOUNTS[@]} -gt 0 ] && echo -e "${BOLD}Mounts ${NC} : ${CYAN}${EXTRA_MOUNTS[*]}${NC}"
echo ""
echo -e "${CYAN}To publish a port from the host:${NC}"
echo -e "  sbx ports ${SANDBOX_NAME} --publish 8080:8080/tcp"
echo ""

if [ ${#CLAUDE_ARGS[@]} -gt 0 ]; then
    sbx run "${SBX_ARGS[@]}" "$AGENT" "${WORKSPACES[@]}" -- "${CLAUDE_ARGS[@]}"
else
    sbx run "${SBX_ARGS[@]}" "$AGENT" "${WORKSPACES[@]}"
fi
