#!/usr/bin/env bash
# =============================================================================
# worktrees.sh - Multi-Agent Git Worktree Management
# =============================================================================
# Provides functions to manage git worktrees for parallel agent execution.
# Each agent gets its own isolated worktree to prevent conflicts.
# =============================================================================

# Default configuration
WORKTREE_BASE_DIR="${WORKTREE_BASE_DIR:-../continuous-claude-worktrees}"
# Note: SWARM_SESSION_ID is set by run_swarm() in coordination.sh
# Only use fallback for standalone worktree operations
if [[ -z "${SWARM_SESSION_ID:-}" ]]; then
    SWARM_SESSION_ID="standalone-$(date +%H%M%S)"
fi

# =============================================================================
# Helper Functions
# =============================================================================

# Check if in a git repository
is_git_repo() {
    git rev-parse --git-dir > /dev/null 2>&1
}

# Get the main repository root directory
get_main_repo_dir() {
    git rev-parse --show-toplevel 2>/dev/null
}

# Get the current branch name
get_current_branch() {
    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main"
}

# Get the default branch (main or master)
get_default_branch() {
    # Try to get the default branch from remote
    local default_branch
    default_branch=$(git remote show origin 2>/dev/null | grep "HEAD branch" | sed 's/.*: //')

    if [[ -z "$default_branch" ]]; then
        # Fallback: check if main or master exists
        if git rev-parse --verify main >/dev/null 2>&1; then
            echo "main"
        elif git rev-parse --verify master >/dev/null 2>&1; then
            echo "master"
        else
            echo "main"  # Ultimate fallback
        fi
    else
        echo "$default_branch"
    fi
}

# Make a path absolute
make_absolute_path() {
    local path="$1"
    local base_dir="$2"

    if [[ "$path" == /* ]]; then
        echo "$path"
    else
        echo "${base_dir}/${path}"
    fi
}

# =============================================================================
# Worktree Naming
# =============================================================================

# Generate a worktree name for an agent
# Usage: get_agent_worktree_name <agent_id> [session_id]
get_agent_worktree_name() {
    local agent_id="$1"
    local session_id="${2:-$SWARM_SESSION_ID}"
    echo "swarm-${session_id}-${agent_id}"
}

# Generate a worktree path for an agent
# Usage: get_agent_worktree_path <agent_id> [session_id]
get_agent_worktree_path() {
    local agent_id="$1"
    local session_id="${2:-$SWARM_SESSION_ID}"
    local worktree_name
    worktree_name=$(get_agent_worktree_name "$agent_id" "$session_id")

    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)

    make_absolute_path "${WORKTREE_BASE_DIR}/${worktree_name}" "$main_repo_dir"
}

# =============================================================================
# Worktree Creation
# =============================================================================

# Create a worktree for an agent
# Usage: create_agent_worktree <agent_id> [branch_name]
# Returns: The worktree path on success
create_agent_worktree() {
    local agent_id="$1"
    local branch_name="${2:-}"

    if ! is_git_repo; then
        echo "Error: Not in a git repository" >&2
        return 1
    fi

    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)

    local worktree_name
    worktree_name=$(get_agent_worktree_name "$agent_id")

    local worktree_path
    worktree_path=$(get_agent_worktree_path "$agent_id")

    # If no branch specified, use agent-specific branch from default branch
    if [[ -z "$branch_name" ]]; then
        local default_branch
        default_branch=$(get_default_branch)
        branch_name="continuous-claude/${agent_id}/${SWARM_SESSION_ID}"
    fi

    # Check if worktree already exists
    if [[ -d "$worktree_path" ]]; then
        echo "Worktree already exists: ${worktree_path}" >&2
        echo "$worktree_path"
        return 0
    fi

    # Ensure base directory exists
    local base_dir
    base_dir=$(dirname "$worktree_path")
    mkdir -p "$base_dir" || {
        echo "Error: Failed to create worktree base directory: ${base_dir}" >&2
        return 1
    }

    # Check if branch exists
    local branch_exists=false
    if git rev-parse --verify "$branch_name" >/dev/null 2>&1; then
        branch_exists=true
    fi

    # Create the worktree
    local default_branch
    default_branch=$(get_default_branch)

    if [[ "$branch_exists" == "true" ]]; then
        # Use existing branch
        if ! git worktree add "$worktree_path" "$branch_name" 2>&1; then
            echo "Error: Failed to create worktree with existing branch: ${branch_name}" >&2
            return 1
        fi
    else
        # Create new branch from default branch
        if ! git worktree add -b "$branch_name" "$worktree_path" "$default_branch" 2>&1; then
            echo "Error: Failed to create worktree with new branch: ${branch_name}" >&2
            return 1
        fi
    fi

    echo "$worktree_path"
    return 0
}

# Create worktrees for multiple agents
# Usage: create_swarm_worktrees <agent_ids_space_separated>
create_swarm_worktrees() {
    local agents="$1"
    local results=()

    for agent_id in $agents; do
        # Capture both stdout and exit status
        local output
        output=$(create_agent_worktree "$agent_id" 2>&1)
        local status=$?

        if [[ $status -eq 0 ]]; then
            # Extract just the path (last line of output)
            local path
            path=$(echo "$output" | tail -1)
            results+=("$agent_id|$path|success")
            echo "✓ Created worktree for ${agent_id}" >&2
        else
            results+=("$agent_id||failed")
            echo "✗ Failed to create worktree for ${agent_id}" >&2
        fi
    done

    # Output JSON array of created worktrees using jq
    local json_items=()
    for entry in "${results[@]}"; do
        IFS='|' read -r agent_id path status <<< "$entry"
        if [[ "$status" == "success" ]]; then
            json_items+=("$(jq -n --arg agent "$agent_id" --arg path "$path" '{agent: $agent, path: $path}')")
        fi
    done

    # Combine into array
    if [[ ${#json_items[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${json_items[@]}" | jq -s '.'
    fi
}

# =============================================================================
# Worktree Management
# =============================================================================

# Get the status of an agent's worktree
# Usage: get_worktree_status <agent_id>
get_worktree_status() {
    local agent_id="$1"
    local worktree_path
    worktree_path=$(get_agent_worktree_path "$agent_id")

    if [[ ! -d "$worktree_path" ]]; then
        echo "not_created"
        return 0
    fi

    # Check if there are uncommitted changes
    if (cd "$worktree_path" && git status --porcelain | grep -q .); then
        echo "dirty"
    else
        echo "clean"
    fi
}

# Get the current branch of an agent's worktree
# Usage: get_worktree_branch <agent_id>
get_worktree_branch() {
    local agent_id="$1"
    local worktree_path
    worktree_path=$(get_agent_worktree_path "$agent_id")

    if [[ ! -d "$worktree_path" ]]; then
        echo "N/A"
        return 1
    fi

    (cd "$worktree_path" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
}

# Sync an agent's worktree with the main branch
# Usage: sync_worktree <agent_id> [target_branch]
sync_worktree() {
    local agent_id="$1"
    local target_branch="${2:-}"

    local worktree_path
    worktree_path=$(get_agent_worktree_path "$agent_id")

    if [[ ! -d "$worktree_path" ]]; then
        echo "Error: Worktree does not exist for agent: ${agent_id}" >&2
        return 1
    fi

    if [[ -z "$target_branch" ]]; then
        target_branch=$(get_default_branch)
    fi

    (
        cd "$worktree_path" || exit 1

        # Fetch latest changes
        git fetch origin "$target_branch" 2>/dev/null

        # Merge or rebase
        if ! git merge "origin/${target_branch}" --no-edit 2>&1; then
            echo "Warning: Merge conflict or error syncing with ${target_branch}" >&2
            return 1
        fi
    )

    echo "Synced ${agent_id} worktree with ${target_branch}"
}

# =============================================================================
# Worktree Cleanup
# =============================================================================

# Remove an agent's worktree
# Usage: remove_agent_worktree <agent_id>
remove_agent_worktree() {
    local agent_id="$1"
    local worktree_path
    worktree_path=$(get_agent_worktree_path "$agent_id")

    if [[ ! -d "$worktree_path" ]]; then
        echo "Worktree does not exist: ${agent_id}" >&2
        return 0
    fi

    # Get main repo directory before removing worktree
    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)

    # Go to main repo first
    if ! cd "$main_repo_dir"; then
        echo "Error: Cannot access main repository" >&2
        return 1
    fi

    # Remove the worktree
    if ! git worktree remove "$worktree_path" --force 2>&1; then
        echo "Warning: git worktree remove failed, trying manual cleanup" >&2
        rm -rf "$worktree_path"
        git worktree prune 2>/dev/null
    fi

    echo "Removed worktree for ${agent_id}"
}

# Remove all worktrees for the current session
# Usage: cleanup_session_worktrees
cleanup_session_worktrees() {
    local session_id="${SWARM_SESSION_ID}"
    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)

    if [[ -z "$main_repo_dir" ]]; then
        echo "Error: Not in a git repository" >&2
        return 1
    fi

    # Find all worktrees for this session
    local worktree_base
    worktree_base=$(make_absolute_path "$WORKTREE_BASE_DIR" "$main_repo_dir")

    if [[ ! -d "$worktree_base" ]]; then
        echo "No worktrees directory found"
        return 0
    fi

    local removed=0
    for worktree_dir in "${worktree_base}"/swarm-${session_id}-*; do
        if [[ -d "$worktree_dir" ]]; then
            local dir_name
            dir_name=$(basename "$worktree_dir")
            echo "Removing: ${dir_name}" >&2

            (cd "$main_repo_dir" && git worktree remove "$worktree_dir" --force 2>/dev/null) || {
                rm -rf "$worktree_dir"
            }
            ((removed++))
        fi
    done

    # Prune worktree references
    (cd "$main_repo_dir" && git worktree prune 2>/dev/null)

    echo "Removed ${removed} worktrees for session ${session_id}"
}

# Remove all swarm worktrees (all sessions)
# Usage: cleanup_all_worktrees
cleanup_all_worktrees() {
    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)

    if [[ -z "$main_repo_dir" ]]; then
        echo "Error: Not in a git repository" >&2
        return 1
    fi

    local worktree_base
    worktree_base=$(make_absolute_path "$WORKTREE_BASE_DIR" "$main_repo_dir")

    if [[ ! -d "$worktree_base" ]]; then
        echo "No worktrees directory found"
        return 0
    fi

    local removed=0
    for worktree_dir in "${worktree_base}"/swarm-*; do
        if [[ -d "$worktree_dir" ]]; then
            local dir_name
            dir_name=$(basename "$worktree_dir")
            echo "Removing: ${dir_name}" >&2

            (cd "$main_repo_dir" && git worktree remove "$worktree_dir" --force 2>/dev/null) || {
                rm -rf "$worktree_dir"
            }
            ((removed++))
        fi
    done

    # Prune worktree references
    (cd "$main_repo_dir" && git worktree prune 2>/dev/null)

    echo "Removed ${removed} swarm worktrees"
}

# =============================================================================
# Worktree Listing
# =============================================================================

# List all worktrees
# Usage: list_all_worktrees
list_all_worktrees() {
    if ! is_git_repo; then
        echo "Error: Not in a git repository" >&2
        return 1
    fi

    git worktree list
}

# List swarm worktrees for current session
# Usage: list_session_worktrees
list_session_worktrees() {
    local session_id="${SWARM_SESSION_ID}"

    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│             Swarm Worktrees (Session: ${session_id})             │"
    echo "├────────────┬────────────────────┬────────────────────────────┤"
    echo "│ Agent      │ Status             │ Branch                     │"
    echo "├────────────┼────────────────────┼────────────────────────────┤"

    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)
    local worktree_base
    worktree_base=$(make_absolute_path "$WORKTREE_BASE_DIR" "$main_repo_dir")

    for worktree_dir in "${worktree_base}"/swarm-${session_id}-*; do
        if [[ -d "$worktree_dir" ]]; then
            local dir_name
            dir_name=$(basename "$worktree_dir")
            # Extract agent id from swarm-SESSION-AGENT
            local agent_id="${dir_name#swarm-${session_id}-}"
            local status
            status=$(get_worktree_status "$agent_id")
            local branch
            branch=$(get_worktree_branch "$agent_id")

            printf "│ %-10s │ %-18s │ %-26s │\n" "$agent_id" "$status" "$branch"
        fi
    done

    echo "╰────────────┴────────────────────┴────────────────────────────╯"
}

# Get worktrees as JSON
# Usage: get_worktrees_json
get_worktrees_json() {
    local session_id="${SWARM_SESSION_ID}"
    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)
    local worktree_base
    worktree_base=$(make_absolute_path "$WORKTREE_BASE_DIR" "$main_repo_dir")

    local json="["
    local first=true

    for worktree_dir in "${worktree_base}"/swarm-${session_id}-*; do
        if [[ -d "$worktree_dir" ]]; then
            local dir_name
            dir_name=$(basename "$worktree_dir")
            local agent_id="${dir_name#swarm-${session_id}-}"
            local status
            status=$(get_worktree_status "$agent_id")
            local branch
            branch=$(get_worktree_branch "$agent_id")

            if [[ "$first" != "true" ]]; then
                json+=","
            fi
            json+="{\"agent\":\"${agent_id}\",\"path\":\"${worktree_dir}\",\"status\":\"${status}\",\"branch\":\"${branch}\"}"
            first=false
        fi
    done

    json+="]"
    echo "$json"
}

# =============================================================================
# Conflict Detection
# =============================================================================

# Check if any worktrees have merge conflicts
# Usage: check_worktree_conflicts
check_worktree_conflicts() {
    local session_id="${SWARM_SESSION_ID}"
    local main_repo_dir
    main_repo_dir=$(get_main_repo_dir)
    local worktree_base
    worktree_base=$(make_absolute_path "$WORKTREE_BASE_DIR" "$main_repo_dir")

    local conflicts=()

    for worktree_dir in "${worktree_base}"/swarm-${session_id}-*; do
        if [[ -d "$worktree_dir" ]]; then
            local has_conflicts
            has_conflicts=$(cd "$worktree_dir" && git ls-files --unmerged 2>/dev/null | wc -l)

            if [[ "$has_conflicts" -gt 0 ]]; then
                local dir_name
                dir_name=$(basename "$worktree_dir")
                local agent_id="${dir_name#swarm-${session_id}-}"
                conflicts+=("$agent_id")
            fi
        fi
    done

    if [[ ${#conflicts[@]} -gt 0 ]]; then
        echo "Conflicts detected in: ${conflicts[*]}"
        return 1
    else
        echo "No conflicts detected"
        return 0
    fi
}

# =============================================================================
# CLI Interface
# =============================================================================

# Main CLI handler
worktrees_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        create)
            create_agent_worktree "${1:-developer}"
            ;;
        create-all)
            create_swarm_worktrees "${1:-developer tester reviewer}"
            ;;
        remove)
            remove_agent_worktree "${1:-}"
            ;;
        cleanup-session)
            cleanup_session_worktrees
            ;;
        cleanup-all)
            cleanup_all_worktrees
            ;;
        list)
            list_session_worktrees
            ;;
        list-all)
            list_all_worktrees
            ;;
        status)
            get_worktree_status "${1:-}"
            ;;
        sync)
            sync_worktree "${1:-}" "${2:-}"
            ;;
        json)
            get_worktrees_json
            ;;
        conflicts)
            check_worktree_conflicts
            ;;
        help|*)
            echo "Usage: worktrees.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  create <agent_id>             Create worktree for an agent"
            echo "  create-all <agents>           Create worktrees for multiple agents"
            echo "  remove <agent_id>             Remove an agent's worktree"
            echo "  cleanup-session               Remove all worktrees for current session"
            echo "  cleanup-all                   Remove all swarm worktrees"
            echo "  list                          List session worktrees"
            echo "  list-all                      List all git worktrees"
            echo "  status <agent_id>             Get worktree status"
            echo "  sync <agent_id> [branch]      Sync worktree with branch"
            echo "  json                          Get worktrees as JSON"
            echo "  conflicts                     Check for merge conflicts"
            echo "  help                          Show this help message"
            echo ""
            echo "Environment Variables:"
            echo "  WORKTREE_BASE_DIR             Base directory for worktrees (default: ../continuous-claude-worktrees)"
            echo "  SWARM_SESSION_ID              Session identifier (default: default)"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    worktrees_cli "$@"
fi
