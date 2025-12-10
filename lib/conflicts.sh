#!/usr/bin/env bash
# =============================================================================
# conflicts.sh - Conflict Detection and Resolution System
# =============================================================================
# Detects and resolves conflicts between agents working on the same codebase.
# Supports sequential, merge, and priority-based resolution strategies.
# =============================================================================

# Configuration
SWARM_DIR="${SWARM_DIR:-.continuous-claude}"
LOCKS_DIR="${SWARM_DIR}/locks"
CONFLICTS_LOG="${SWARM_DIR}/state/conflicts.json"

# Resolution strategies
STRATEGY_SEQUENTIAL="sequential"    # Wait for other agent to finish
STRATEGY_MERGE="merge"              # Attempt automatic merge
STRATEGY_PRIORITY="priority"        # Higher priority agent wins
STRATEGY_MANUAL="manual"            # Escalate to human

# =============================================================================
# Lock Management
# =============================================================================

# Initialize locks directory
init_locks() {
    mkdir -p "${LOCKS_DIR}"
}

# Acquire a lock on a file/resource
# Usage: acquire_lock <agent_id> <resource_path> [timeout_seconds]
acquire_lock() {
    local agent_id="$1"
    local resource="$2"
    local timeout="${3:-30}"

    init_locks

    # Normalize resource path to create lock file name
    local lock_name
    lock_name=$(echo "$resource" | sed 's/[\/:]/_/g')
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"

    local start_time
    start_time=$(date +%s)

    while true; do
        # Try to create lock file atomically
        if (set -o noclobber; echo "$agent_id:$(date +%s)" > "$lock_file") 2>/dev/null; then
            echo "Lock acquired: ${resource}"
            return 0
        fi

        # Check if lock is stale (older than 5 minutes)
        if [[ -f "$lock_file" ]]; then
            local lock_content lock_time
            lock_content=$(cat "$lock_file" 2>/dev/null || echo "")
            lock_time="${lock_content#*:}"

            if [[ -n "$lock_time" ]]; then
                local current_time
                current_time=$(date +%s)
                local lock_age=$((current_time - lock_time))

                if [[ $lock_age -gt 300 ]]; then
                    # Lock is stale, remove it
                    rm -f "$lock_file"
                    echo "Removed stale lock: ${resource}" >&2
                    continue
                fi
            fi
        fi

        # Check timeout
        local current_time
        current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [[ $elapsed -ge $timeout ]]; then
            echo "Lock timeout: ${resource}" >&2
            return 1
        fi

        # Wait and retry
        sleep 1
    done
}

# Release a lock
# Usage: release_lock <agent_id> <resource_path>
release_lock() {
    local agent_id="$1"
    local resource="$2"

    local lock_name
    lock_name=$(echo "$resource" | sed 's/[\/:]/_/g')
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"

    if [[ -f "$lock_file" ]]; then
        local lock_owner
        lock_owner=$(cat "$lock_file" 2>/dev/null | cut -d: -f1)

        if [[ "$lock_owner" == "$agent_id" ]]; then
            rm -f "$lock_file"
            echo "Lock released: ${resource}"
            return 0
        else
            echo "Error: Lock owned by ${lock_owner}, not ${agent_id}" >&2
            return 1
        fi
    fi

    return 0
}

# Check if a resource is locked
# Usage: is_locked <resource_path>
is_locked() {
    local resource="$1"

    local lock_name
    lock_name=$(echo "$resource" | sed 's/[\/:]/_/g')
    local lock_file="${LOCKS_DIR}/${lock_name}.lock"

    if [[ -f "$lock_file" ]]; then
        local lock_content
        lock_content=$(cat "$lock_file" 2>/dev/null || echo "")
        echo "$lock_content"
        return 0
    fi

    return 1
}

# Get lock owner
# Usage: get_lock_owner <resource_path>
get_lock_owner() {
    local resource="$1"
    local lock_info
    lock_info=$(is_locked "$resource")

    if [[ -n "$lock_info" ]]; then
        echo "${lock_info%%:*}"
    fi
}

# List all active locks
list_locks() {
    init_locks

    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│                      Active Locks                             │"
    echo "├────────────────────────┬────────────────┬────────────────────┤"
    echo "│ Resource               │ Owner          │ Age (seconds)      │"
    echo "├────────────────────────┼────────────────┼────────────────────┤"

    local current_time
    current_time=$(date +%s)

    for lock_file in "${LOCKS_DIR}"/*.lock; do
        if [[ -f "$lock_file" ]]; then
            local resource
            resource=$(basename "$lock_file" .lock | sed 's/_/\//g')
            local lock_content
            lock_content=$(cat "$lock_file" 2>/dev/null || echo ":")
            local owner="${lock_content%%:*}"
            local lock_time="${lock_content#*:}"
            local age=$((current_time - lock_time))

            printf "│ %-22s │ %-14s │ %-18s │\n" "${resource:0:22}" "$owner" "$age"
        fi
    done

    echo "╰────────────────────────┴────────────────┴────────────────────╯"
}

# =============================================================================
# Conflict Detection
# =============================================================================

# Detect file-level conflicts between agent changes
# Usage: detect_conflicts <agent1_id> <agent2_id>
detect_conflicts() {
    local agent1="$1"
    local agent2="$2"

    # Get worktree paths (assuming worktrees.sh is sourced)
    local path1 path2
    path1=$(get_agent_worktree_path "$agent1" 2>/dev/null)
    path2=$(get_agent_worktree_path "$agent2" 2>/dev/null)

    if [[ ! -d "$path1" || ! -d "$path2" ]]; then
        echo "[]"
        return 0
    fi

    # Get modified files in each worktree
    local files1 files2
    files1=$(cd "$path1" && git diff --name-only HEAD 2>/dev/null | sort)
    files2=$(cd "$path2" && git diff --name-only HEAD 2>/dev/null | sort)

    # Find common files (potential conflicts)
    local conflicts=()
    while IFS= read -r file; do
        if [[ -n "$file" ]] && echo "$files2" | grep -q "^${file}$"; then
            conflicts+=("$file")
        fi
    done <<< "$files1"

    # Output as JSON
    if [[ ${#conflicts[@]} -eq 0 ]]; then
        echo "[]"
    else
        printf '%s\n' "${conflicts[@]}" | jq -R . | jq -s '.'
    fi
}

# Detect conflicts across all active agents
# Usage: detect_all_conflicts
detect_all_conflicts() {
    local state_file="${SWARM_DIR}/state/agents.json"

    if [[ ! -f "$state_file" ]]; then
        echo "[]"
        return 0
    fi

    local agents
    agents=$(cat "$state_file" | jq -r 'keys[]')

    local all_conflicts="[]"
    local checked=()

    for agent1 in $agents; do
        for agent2 in $agents; do
            # Skip self and already checked pairs
            if [[ "$agent1" == "$agent2" ]]; then
                continue
            fi

            local pair="${agent1}-${agent2}"
            local reverse_pair="${agent2}-${agent1}"

            if [[ " ${checked[*]} " =~ " ${reverse_pair} " ]]; then
                continue
            fi

            checked+=("$pair")

            local conflicts
            conflicts=$(detect_conflicts "$agent1" "$agent2")

            if [[ "$conflicts" != "[]" ]]; then
                local conflict_record
                conflict_record=$(jq -n \
                    --arg a1 "$agent1" \
                    --arg a2 "$agent2" \
                    --argjson files "$conflicts" \
                    '{agents: [$a1, $a2], files: $files}'
                )

                all_conflicts=$(echo "$all_conflicts" | jq --argjson c "$conflict_record" '. + [$c]')
            fi
        done
    done

    echo "$all_conflicts"
}

# =============================================================================
# Conflict Resolution
# =============================================================================

# Resolve a conflict using the specified strategy
# Usage: resolve_conflict <strategy> <agent1> <agent2> <file_path>
resolve_conflict() {
    local strategy="$1"
    local agent1="$2"
    local agent2="$3"
    local file_path="$4"

    local result
    result=$(jq -n \
        --arg strategy "$strategy" \
        --arg file "$file_path" \
        --arg agent1 "$agent1" \
        --arg agent2 "$agent2" \
        --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
        '{
            strategy: $strategy,
            file: $file,
            agents: [$agent1, $agent2],
            timestamp: $timestamp
        }'
    )

    case "$strategy" in
        "$STRATEGY_SEQUENTIAL")
            result=$(resolve_sequential "$agent1" "$agent2" "$file_path")
            ;;
        "$STRATEGY_MERGE")
            result=$(resolve_merge "$agent1" "$agent2" "$file_path")
            ;;
        "$STRATEGY_PRIORITY")
            result=$(resolve_priority "$agent1" "$agent2" "$file_path")
            ;;
        "$STRATEGY_MANUAL")
            result=$(resolve_manual "$agent1" "$agent2" "$file_path")
            ;;
        *)
            echo "Error: Unknown strategy: ${strategy}" >&2
            return 1
            ;;
    esac

    # Log the resolution
    log_conflict_resolution "$result"

    echo "$result"
}

# Sequential resolution - second agent waits
resolve_sequential() {
    local agent1="$1"
    local agent2="$2"
    local file_path="$3"

    # Agent1 gets priority, agent2 must wait
    echo "Sequential resolution: ${agent1} proceeds, ${agent2} waits" >&2

    # Acquire lock for agent1 (suppress normal output)
    if acquire_lock "$agent1" "$file_path" 5 >/dev/null 2>&1; then
        jq -n \
            --arg winner "$agent1" \
            --arg waiter "$agent2" \
            --arg file "$file_path" \
            '{
                status: "resolved",
                resolution: "sequential",
                winner: $winner,
                waiter: $waiter,
                file: $file,
                action: "agent2_must_wait"
            }'
    else
        jq -n \
            --arg file "$file_path" \
            '{
                status: "failed",
                resolution: "sequential",
                error: "could_not_acquire_lock",
                file: $file
            }'
    fi
}

# Merge resolution - attempt automatic merge
resolve_merge() {
    local agent1="$1"
    local agent2="$2"
    local file_path="$3"

    local path1 path2
    path1=$(get_agent_worktree_path "$agent1" 2>/dev/null)
    path2=$(get_agent_worktree_path "$agent2" 2>/dev/null)

    echo "Attempting automatic merge for: ${file_path}" >&2

    # Try 3-way merge using git merge-file
    local base_file="${path1}/${file_path}"
    local our_file="${path1}/${file_path}"
    local their_file="${path2}/${file_path}"

    if [[ ! -f "$our_file" || ! -f "$their_file" ]]; then
        jq -n \
            --arg file "$file_path" \
            '{
                status: "failed",
                resolution: "merge",
                error: "file_not_found",
                file: $file
            }'
        return 1
    fi

    # Create temp files for merge
    local temp_dir
    temp_dir=$(mktemp -d)
    cp "$our_file" "${temp_dir}/ours"
    cp "$their_file" "${temp_dir}/theirs"

    # Get base version (common ancestor)
    local base_content
    base_content=$(cd "$path1" && git show HEAD:"$file_path" 2>/dev/null)
    echo "$base_content" > "${temp_dir}/base"

    # Attempt merge
    if git merge-file -p "${temp_dir}/ours" "${temp_dir}/base" "${temp_dir}/theirs" > "${temp_dir}/merged" 2>/dev/null; then
        jq -n \
            --arg file "$file_path" \
            --arg merged "${temp_dir}/merged" \
            '{
                status: "resolved",
                resolution: "merge",
                file: $file,
                merged_file: $merged,
                action: "auto_merged"
            }'
    else
        # Merge conflict
        jq -n \
            --arg file "$file_path" \
            '{
                status: "conflict",
                resolution: "merge",
                file: $file,
                action: "manual_intervention_required"
            }'
    fi

    rm -rf "$temp_dir"
}

# Priority resolution - higher priority agent wins
resolve_priority() {
    local agent1="$1"
    local agent2="$2"
    local file_path="$3"

    # Get agent priorities (developer > tester > reviewer > others)
    local priority1 priority2
    priority1=$(get_agent_priority "$agent1")
    priority2=$(get_agent_priority "$agent2")

    local winner loser
    if [[ $priority1 -le $priority2 ]]; then
        winner="$agent1"
        loser="$agent2"
    else
        winner="$agent2"
        loser="$agent1"
    fi

    echo "Priority resolution: ${winner} (priority ${priority1}) wins over ${loser}" >&2

    jq -n \
        --arg winner "$winner" \
        --arg loser "$loser" \
        --arg file "$file_path" \
        --argjson p1 "$priority1" \
        --argjson p2 "$priority2" \
        '{
            status: "resolved",
            resolution: "priority",
            winner: $winner,
            loser: $loser,
            file: $file,
            priority_winner: $p1,
            priority_loser: $p2,
            action: "winner_changes_kept"
        }'
}

# Manual resolution - escalate to human
resolve_manual() {
    local agent1="$1"
    local agent2="$2"
    local file_path="$3"

    echo "⚠️  Manual resolution required for: ${file_path}" >&2
    echo "   Agents: ${agent1}, ${agent2}" >&2

    jq -n \
        --arg agent1 "$agent1" \
        --arg agent2 "$agent2" \
        --arg file "$file_path" \
        '{
            status: "pending",
            resolution: "manual",
            agents: [$agent1, $agent2],
            file: $file,
            action: "awaiting_human_decision"
        }'
}

# Get agent priority (lower number = higher priority)
get_agent_priority() {
    local agent_id="$1"

    case "$agent_id" in
        developer*) echo 1 ;;
        tester*) echo 2 ;;
        reviewer*) echo 3 ;;
        security*) echo 4 ;;
        documenter*) echo 5 ;;
        *) echo 10 ;;
    esac
}

# =============================================================================
# Conflict Logging
# =============================================================================

# Log a conflict resolution
log_conflict_resolution() {
    local resolution="$1"

    local log_file="${CONFLICTS_LOG}"
    mkdir -p "$(dirname "$log_file")"

    local current_log
    if [[ -f "$log_file" ]]; then
        current_log=$(cat "$log_file")
    else
        current_log="[]"
    fi

    local updated
    updated=$(echo "$current_log" | jq --argjson r "$resolution" '. + [$r]')

    echo "$updated" > "$log_file"
}

# Get conflict history
get_conflict_history() {
    local log_file="${CONFLICTS_LOG}"

    if [[ -f "$log_file" ]]; then
        cat "$log_file"
    else
        echo "[]"
    fi
}

# Print conflict history
print_conflict_history() {
    local history
    history=$(get_conflict_history)

    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│                    Conflict History                           │"
    echo "├───────────────────────────────────────────────────────────────┤"

    echo "$history" | jq -r '.[] | "│ \(.timestamp // "N/A") | \(.resolution // "N/A") | \(.file // "N/A")"'

    echo "╰───────────────────────────────────────────────────────────────╯"
}

# =============================================================================
# CLI Interface
# =============================================================================

conflicts_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        detect)
            detect_conflicts "${1:-}" "${2:-}"
            ;;
        detect-all)
            detect_all_conflicts
            ;;
        resolve)
            resolve_conflict "${1:-sequential}" "${2:-}" "${3:-}" "${4:-}"
            ;;
        lock)
            acquire_lock "${1:-}" "${2:-}" "${3:-30}"
            ;;
        unlock)
            release_lock "${1:-}" "${2:-}"
            ;;
        check-lock)
            is_locked "${1:-}"
            ;;
        list-locks)
            list_locks
            ;;
        history)
            print_conflict_history
            ;;
        help|*)
            echo "Usage: conflicts.sh <command> [args]"
            echo ""
            echo "Detection:"
            echo "  detect <agent1> <agent2>     Detect conflicts between two agents"
            echo "  detect-all                   Detect all conflicts in swarm"
            echo ""
            echo "Resolution:"
            echo "  resolve <strategy> <a1> <a2> <file>"
            echo "    Strategies: sequential, merge, priority, manual"
            echo ""
            echo "Locking:"
            echo "  lock <agent> <resource> [timeout]"
            echo "  unlock <agent> <resource>"
            echo "  check-lock <resource>"
            echo "  list-locks"
            echo ""
            echo "History:"
            echo "  history                      Show conflict resolution history"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    conflicts_cli "$@"
fi
