#!/usr/bin/env bash
# =============================================================================
# orchestrator.sh - Multi-Agent Orchestration Engine
# =============================================================================
# Manages the lifecycle of multiple agents, distributes tasks, and coordinates
# their activities in the swarm.
# =============================================================================

# Source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/messaging.sh"
source "${SCRIPT_DIR}/personas.sh"
source "${SCRIPT_DIR}/worktrees.sh"

# =============================================================================
# Configuration
# =============================================================================

SWARM_DIR="${SWARM_DIR:-.continuous-claude}"
STATE_DIR="${SWARM_DIR}/state"
# Use timestamp + PID + random for unique session ID
SWARM_SESSION_ID="${SWARM_SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$-$(printf '%04x' $RANDOM)}"

# Agent states are stored in JSON files for bash 3 compatibility
# State is managed through STATE_DIR/agents.json

# =============================================================================
# State Management
# =============================================================================

# Initialize state directory
init_state() {
    mkdir -p "${STATE_DIR}"

    # Create initial state files
    echo "{}" > "${STATE_DIR}/agents.json"
    echo "[]" > "${STATE_DIR}/tasks.json"
    echo "{\"session_id\": \"${SWARM_SESSION_ID}\", \"status\": \"initializing\", \"started_at\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"}" > "${STATE_DIR}/session.json"
}

# Update agent state
# Usage: update_agent_state <agent_id> <status> [extra_json]
update_agent_state() {
    local agent_id="$1"
    local status="$2"
    local extra="${3:-"{}"}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local state_file="${STATE_DIR}/agents.json"

    # Read current state
    local current_state
    if [[ -f "$state_file" ]]; then
        current_state=$(cat "$state_file")
    else
        current_state="{}"
    fi

    # Update agent's state
    local updated
    updated=$(echo "$current_state" | jq \
        --arg id "$agent_id" \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson extra "$extra" \
        '.[$id] = (.[$id] // {}) + {status: $status, last_updated: $timestamp} + $extra'
    )

    echo "$updated" > "$state_file"
}

# Get agent state
# Usage: get_agent_state <agent_id>
get_agent_state() {
    local agent_id="$1"
    local state_file="${STATE_DIR}/agents.json"

    if [[ -f "$state_file" ]]; then
        jq -r --arg id "$agent_id" '.[$id] // empty' "$state_file"
    fi
}

# Get all agents state
get_all_agents_state() {
    local state_file="${STATE_DIR}/agents.json"

    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "{}"
    fi
}

# Update session state
# Usage: update_session_state <status> [extra_json]
update_session_state() {
    local status="$1"
    local extra="${2:-"{}"}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local state_file="${STATE_DIR}/session.json"

    local current_state
    if [[ -f "$state_file" ]]; then
        current_state=$(cat "$state_file")
    else
        current_state="{}"
    fi

    local updated
    updated=$(echo "$current_state" | jq \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson extra "$extra" \
        '. + {status: $status, last_updated: $timestamp} + $extra'
    )

    echo "$updated" > "$state_file"
}

# Get session state
get_session_state() {
    local state_file="${STATE_DIR}/session.json"

    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "{}"
    fi
}

# =============================================================================
# Task Queue Management
# =============================================================================

# Add a task to the queue
# Usage: add_task <type> <agent_id> <description> [priority] [payload_json]
add_task() {
    local task_type="$1"
    local agent_id="$2"
    local description="$3"
    local priority="${4:-5}"
    local payload="${5:-"{}"}"

    local task_id="task-$(date +%Y%m%d%H%M%S)-$(openssl rand -hex 4)"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tasks_file="${STATE_DIR}/tasks.json"

    local current_tasks
    if [[ -f "$tasks_file" ]]; then
        current_tasks=$(cat "$tasks_file")
    else
        current_tasks="[]"
    fi

    local new_task
    new_task=$(jq -n \
        --arg id "$task_id" \
        --arg type "$task_type" \
        --arg agent "$agent_id" \
        --arg desc "$description" \
        --argjson priority "$priority" \
        --argjson payload "$payload" \
        --arg status "pending" \
        --arg created "$timestamp" \
        '{
            id: $id,
            type: $type,
            agent: $agent,
            description: $desc,
            priority: $priority,
            payload: $payload,
            status: $status,
            created_at: $created
        }'
    )

    local updated
    updated=$(echo "$current_tasks" | jq --argjson task "$new_task" '. + [$task]')

    echo "$updated" > "$tasks_file"
    echo "$task_id"
}

# Update task status
# Usage: update_task_status <task_id> <status> [result_json]
update_task_status() {
    local task_id="$1"
    local status="$2"
    local result="${3:-"{}"}"
    local timestamp
    timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    local tasks_file="${STATE_DIR}/tasks.json"

    if [[ ! -f "$tasks_file" ]]; then
        return 1
    fi

    local updated
    updated=$(cat "$tasks_file" | jq \
        --arg id "$task_id" \
        --arg status "$status" \
        --arg timestamp "$timestamp" \
        --argjson result "$result" \
        'map(if .id == $id then . + {status: $status, updated_at: $timestamp, result: $result} else . end)'
    )

    echo "$updated" > "$tasks_file"
}

# Get pending tasks for an agent
# Usage: get_pending_tasks <agent_id>
get_pending_tasks() {
    local agent_id="$1"
    local tasks_file="${STATE_DIR}/tasks.json"

    if [[ ! -f "$tasks_file" ]]; then
        echo "[]"
        return
    fi

    cat "$tasks_file" | jq --arg agent "$agent_id" \
        '[.[] | select(.agent == $agent and .status == "pending")] | sort_by(.priority)'
}

# Get next task for an agent (highest priority pending task)
# Usage: get_next_task <agent_id>
get_next_task() {
    local agent_id="$1"
    get_pending_tasks "$agent_id" | jq 'first // empty'
}

# Get task queue summary
get_task_queue_summary() {
    local tasks_file="${STATE_DIR}/tasks.json"

    if [[ ! -f "$tasks_file" ]]; then
        echo '{"pending": 0, "in_progress": 0, "completed": 0, "failed": 0}'
        return
    fi

    cat "$tasks_file" | jq '{
        pending: [.[] | select(.status == "pending")] | length,
        in_progress: [.[] | select(.status == "in_progress")] | length,
        completed: [.[] | select(.status == "completed")] | length,
        failed: [.[] | select(.status == "failed")] | length
    }'
}

# =============================================================================
# Agent Lifecycle Management
# =============================================================================

# Register an agent in the swarm
# Usage: register_agent <agent_id> <persona_id>
register_agent() {
    local agent_id="$1"
    local persona_id="${2:-$agent_id}"

    # Load persona
    local persona
    persona=$(load_persona "$persona_id")

    if [[ -z "$persona" ]]; then
        echo "Error: Could not load persona: ${persona_id}" >&2
        return 1
    fi

    local emoji name
    emoji=$(get_persona_emoji "$persona")
    name=$(get_persona_name "$persona")

    # Create worktree for agent
    local worktree_path
    worktree_path=$(create_agent_worktree "$agent_id")

    if [[ $? -ne 0 ]]; then
        echo "Error: Could not create worktree for agent: ${agent_id}" >&2
        return 1
    fi

    # Initialize messaging for agent
    init_messaging "$agent_id"

    # Update state
    update_agent_state "$agent_id" "registered" "$(jq -n \
        --arg persona "$persona_id" \
        --arg emoji "$emoji" \
        --arg name "$name" \
        --arg worktree "$worktree_path" \
        '{persona: $persona, emoji: $emoji, name: $name, worktree: $worktree, iteration: 0}'
    )"

    echo "${emoji} Registered agent: ${name} (${agent_id})"
}

# Start an agent
# Usage: start_agent <agent_id>
start_agent() {
    local agent_id="$1"

    update_agent_state "$agent_id" "running" '{"started_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

    echo "Started agent: ${agent_id}"
}

# Stop an agent
# Usage: stop_agent <agent_id>
stop_agent() {
    local agent_id="$1"

    update_agent_state "$agent_id" "stopped" '{"stopped_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

    echo "Stopped agent: ${agent_id}"
}

# Increment agent iteration
# Usage: increment_iteration <agent_id>
increment_iteration() {
    local agent_id="$1"

    local current_state
    current_state=$(get_agent_state "$agent_id")

    if [[ -z "$current_state" ]]; then
        return 1
    fi

    local current_iteration
    current_iteration=$(echo "$current_state" | jq -r '.iteration // 0')
    local new_iteration=$((current_iteration + 1))

    update_agent_state "$agent_id" "running" "{\"iteration\": $new_iteration}"

    echo "$new_iteration"
}

# Unregister an agent
# Usage: unregister_agent <agent_id>
unregister_agent() {
    local agent_id="$1"

    # Remove worktree
    remove_agent_worktree "$agent_id"

    # Update state
    update_agent_state "$agent_id" "unregistered"

    echo "Unregistered agent: ${agent_id}"
}

# =============================================================================
# Swarm Initialization
# =============================================================================

# Initialize the swarm with specified agents
# Usage: init_swarm <agent_list> [prompt]
# agent_list: space-separated list of agent IDs (e.g., "developer tester reviewer")
init_swarm() {
    local agent_list="$1"
    local prompt="${2:-}"

    echo "🐝 Initializing Swarm"
    echo "   Session: ${SWARM_SESSION_ID}"
    echo "   Agents: ${agent_list}"
    echo ""

    # Initialize state
    init_state
    init_all_messaging

    # Update session state with prompt
    if [[ -n "$prompt" ]]; then
        update_session_state "initializing" "$(jq -n --arg prompt "$prompt" '{prompt: $prompt}')"
    fi

    # Register each agent
    local registered_agents=()
    for agent_id in $agent_list; do
        if register_agent "$agent_id" "$agent_id" 2>/dev/null; then
            registered_agents+=("$agent_id")
        else
            echo "⚠️  Warning: Could not register agent: ${agent_id}" >&2
        fi
    done

    # Update session state
    update_session_state "ready" "$(jq -n \
        --argjson agents "$(printf '%s\n' "${registered_agents[@]}" | jq -R . | jq -s .)" \
        '{agents: $agents}'
    )"

    echo ""
    echo "✅ Swarm initialized with ${#registered_agents[@]} agents"

    # Return JSON summary
    jq -n \
        --arg session "$SWARM_SESSION_ID" \
        --argjson agents "$(printf '%s\n' "${registered_agents[@]}" | jq -R . | jq -s .)" \
        '{session_id: $session, agents: $agents, status: "ready"}'
}

# Shutdown the swarm
# Usage: shutdown_swarm
shutdown_swarm() {
    echo "🛑 Shutting down Swarm"

    # Get all registered agents
    local agents_state
    agents_state=$(get_all_agents_state)

    local agent_ids
    agent_ids=$(echo "$agents_state" | jq -r 'keys[]')

    # Stop and unregister each agent
    for agent_id in $agent_ids; do
        local status
        status=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].status // "unknown"')

        if [[ "$status" != "unregistered" ]]; then
            stop_agent "$agent_id"
            unregister_agent "$agent_id"
        fi
    done

    # Update session state
    update_session_state "shutdown" '{"ended_at": "'$(date -u +"%Y-%m-%dT%H:%M:%SZ")'"}'

    # Cleanup worktrees
    cleanup_session_worktrees

    echo "✅ Swarm shutdown complete"
}

# =============================================================================
# Coordination
# =============================================================================

# Distribute initial tasks to agents based on prompt
# Usage: distribute_initial_tasks <prompt>
distribute_initial_tasks() {
    local prompt="$1"

    # Get registered agents
    local agents_state
    agents_state=$(get_all_agents_state)

    # Find developer agent and assign main task
    local has_developer
    has_developer=$(echo "$agents_state" | jq -r '.developer // empty')

    if [[ -n "$has_developer" ]]; then
        # Create main development task
        local task_id
        task_id=$(add_task "implementation" "developer" "$prompt" 1 "$(jq -n --arg prompt "$prompt" '{original_prompt: $prompt}')")

        # Send task assignment message
        send_task_assignment "orchestrator" "developer" "$prompt" "{\"task_id\": \"$task_id\"}"

        # Start the developer
        start_agent "developer"

        echo "📋 Assigned initial task to developer: ${task_id}"
    fi

    # Put other agents in waiting state
    for agent_id in $(echo "$agents_state" | jq -r 'keys[]'); do
        if [[ "$agent_id" != "developer" ]]; then
            update_agent_state "$agent_id" "waiting"
        fi
    done
}

# Process agent completion signal
# Usage: process_agent_signal <agent_id> <signal_type> [payload_json]
process_agent_signal() {
    local agent_id="$1"
    local signal_type="$2"
    local payload="${3:-"{}"}"

    case "$signal_type" in
        "feature_complete")
            # Developer finished feature, notify tester
            local feature
            feature=$(echo "$payload" | jq -r '.feature // "unknown"')
            local files
            files=$(echo "$payload" | jq -c '.files // []')

            send_feature_complete "$agent_id" "$feature" "$files"

            # Activate tester if registered
            local tester_state
            tester_state=$(get_agent_state "tester")
            if [[ -n "$tester_state" ]]; then
                start_agent "tester"
                add_task "testing" "tester" "Test feature: ${feature}" 2 "$payload"
            fi
            ;;

        "tests_passed")
            # Tester completed, notify reviewer
            local summary
            summary=$(echo "$payload" | jq -c '.summary // {}')

            send_test_results "passed" "$summary"

            # Activate reviewer if registered
            local reviewer_state
            reviewer_state=$(get_agent_state "reviewer")
            if [[ -n "$reviewer_state" ]]; then
                start_agent "reviewer"
                add_task "review" "reviewer" "Review tested code" 2 "$payload"
            fi
            ;;

        "tests_failed")
            # Tests failed, notify developer
            local details
            details=$(echo "$payload" | jq -c '.details // {}')

            send_test_results "failed" '{}' "$details"

            # Developer needs to fix
            add_task "bugfix" "developer" "Fix failing tests" 1 "$payload"
            start_agent "developer"
            ;;

        "review_approved")
            # Code approved, can merge
            local pr_number
            pr_number=$(echo "$payload" | jq -r '.pr_number // ""')

            send_review_feedback "approve" '[]' "$pr_number"

            echo "🎉 Code approved! Ready for merge."
            update_session_state "completed" '{"result": "approved"}'
            ;;

        "review_changes_requested")
            # Changes requested, notify developer
            local comments
            comments=$(echo "$payload" | jq -c '.comments // []')

            send_review_feedback "request_changes" "$comments"

            # Developer needs to address feedback
            add_task "revision" "developer" "Address review feedback" 1 "$payload"
            start_agent "developer"
            ;;

        *)
            echo "Unknown signal type: ${signal_type}" >&2
            return 1
            ;;
    esac
}

# Check and process pending messages for all agents
# Usage: process_pending_messages
process_pending_messages() {
    # Deliver any pending outbox messages
    deliver_messages

    # Get all registered agents
    local agents_state
    agents_state=$(get_all_agents_state)

    local processed=0

    for agent_id in $(echo "$agents_state" | jq -r 'keys[]'); do
        local status
        status=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].status // "unknown"')

        # Only process for waiting agents
        if [[ "$status" == "waiting" ]]; then
            local unread
            unread=$(get_unread_count "$agent_id")

            if [[ "$unread" -gt 0 ]]; then
                echo "📬 ${agent_id} has ${unread} unread message(s)"
                ((processed++))
            fi
        fi
    done

    echo "$processed"
}

# =============================================================================
# Status and Monitoring
# =============================================================================

# Print swarm status
print_swarm_status() {
    local session
    session=$(get_session_state)

    local session_id status started_at
    session_id=$(echo "$session" | jq -r '.session_id // "unknown"')
    status=$(echo "$session" | jq -r '.status // "unknown"')
    started_at=$(echo "$session" | jq -r '.started_at // "N/A"')

    echo "╭───────────────────────────────────────────────────────────────╮"
    echo "│                    🐝 Swarm Status                            │"
    echo "├───────────────────────────────────────────────────────────────┤"
    printf "│ Session: %-52s │\n" "$session_id"
    printf "│ Status: %-53s │\n" "$status"
    printf "│ Started: %-52s │\n" "$started_at"
    echo "├───────────────────────────────────────────────────────────────┤"
    echo "│                         Agents                                │"
    echo "├────────────┬────────────────┬───────────┬────────────────────┤"
    echo "│ Agent      │ Status         │ Iteration │ Unread Msgs        │"
    echo "├────────────┼────────────────┼───────────┼────────────────────┤"

    local agents_state
    agents_state=$(get_all_agents_state)

    for agent_id in $(echo "$agents_state" | jq -r 'keys[]' | sort); do
        local agent_status iteration emoji unread
        agent_status=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].status // "unknown"')
        iteration=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].iteration // 0')
        emoji=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].emoji // "?"')
        unread=$(get_unread_count "$agent_id")

        printf "│ %s %-8s │ %-14s │ %-9s │ %-18s │\n" "$emoji" "$agent_id" "$agent_status" "$iteration" "$unread"
    done

    echo "├────────────┴────────────────┴───────────┴────────────────────┤"

    # Task queue summary
    local task_summary
    task_summary=$(get_task_queue_summary)

    local pending in_progress completed failed
    pending=$(echo "$task_summary" | jq -r '.pending')
    in_progress=$(echo "$task_summary" | jq -r '.in_progress')
    completed=$(echo "$task_summary" | jq -r '.completed')
    failed=$(echo "$task_summary" | jq -r '.failed')

    echo "│                        Task Queue                             │"
    echo "├───────────────────────────────────────────────────────────────┤"
    printf "│ Pending: %-5s  In Progress: %-5s  Done: %-5s  Failed: %-4s │\n" "$pending" "$in_progress" "$completed" "$failed"
    echo "╰───────────────────────────────────────────────────────────────╯"
}

# Get swarm status as JSON
get_swarm_status_json() {
    local session
    session=$(get_session_state)

    local agents_state
    agents_state=$(get_all_agents_state)

    local task_summary
    task_summary=$(get_task_queue_summary)

    jq -n \
        --argjson session "$session" \
        --argjson agents "$agents_state" \
        --argjson tasks "$task_summary" \
        '{
            session: $session,
            agents: $agents,
            task_queue: $tasks
        }'
}

# =============================================================================
# CLI Interface
# =============================================================================

orchestrator_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        init)
            local agents="${1:-developer tester reviewer}"
            local prompt="${2:-}"
            init_swarm "$agents" "$prompt"
            ;;
        shutdown)
            shutdown_swarm
            ;;
        status)
            print_swarm_status
            ;;
        status-json)
            get_swarm_status_json
            ;;
        register)
            register_agent "${1:-}" "${2:-}"
            ;;
        start)
            start_agent "${1:-}"
            ;;
        stop)
            stop_agent "${1:-}"
            ;;
        signal)
            process_agent_signal "${1:-}" "${2:-}" "${3:-"{}"}"
            ;;
        add-task)
            add_task "${1:-}" "${2:-}" "${3:-}" "${4:-5}" "${5:-"{}"}"
            ;;
        next-task)
            get_next_task "${1:-}"
            ;;
        distribute)
            distribute_initial_tasks "${1:-}"
            ;;
        process-messages)
            process_pending_messages
            ;;
        help|*)
            echo "Usage: orchestrator.sh <command> [args]"
            echo ""
            echo "Swarm Commands:"
            echo "  init <agents> [prompt]       Initialize swarm with agents"
            echo "  shutdown                     Shutdown the swarm"
            echo "  status                       Print swarm status"
            echo "  status-json                  Get status as JSON"
            echo ""
            echo "Agent Commands:"
            echo "  register <id> [persona]      Register an agent"
            echo "  start <id>                   Start an agent"
            echo "  stop <id>                    Stop an agent"
            echo "  signal <id> <type> [payload] Process agent signal"
            echo ""
            echo "Task Commands:"
            echo "  add-task <type> <agent> <desc> [priority] [payload]"
            echo "  next-task <agent>            Get next task for agent"
            echo "  distribute <prompt>          Distribute initial tasks"
            echo ""
            echo "Communication:"
            echo "  process-messages             Process pending messages"
            echo ""
            echo "Environment Variables:"
            echo "  SWARM_SESSION_ID             Session identifier"
            echo "  SWARM_DIR                    State directory"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    orchestrator_cli "$@"
fi
