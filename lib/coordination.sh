#!/usr/bin/env bash
# =============================================================================
# coordination.sh - Agent Coordination and Communication Layer
# =============================================================================
# High-level coordination functions that integrate messaging, personas,
# worktrees, conflicts, and orchestration into a unified API.
# =============================================================================

# Source all dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/messaging.sh"
source "${SCRIPT_DIR}/personas.sh"
source "${SCRIPT_DIR}/worktrees.sh"
source "${SCRIPT_DIR}/conflicts.sh"
source "${SCRIPT_DIR}/orchestrator.sh"

# =============================================================================
# Configuration
# =============================================================================

COORDINATION_MODE="${COORDINATION_MODE:-pipeline}"  # pipeline, parallel, adaptive
AUTO_MERGE="${AUTO_MERGE:-false}"
# Note: VERBOSE is set by the caller (continuous_claude.sh) via export

# =============================================================================
# Workflow Definitions
# =============================================================================

# Standard development workflow:
# developer -> tester -> reviewer -> (merge or developer)
WORKFLOW_PIPELINE="developer:tester:reviewer"

# Parallel workflow with sync points
WORKFLOW_PARALLEL="developer,tester:reviewer"

# =============================================================================
# Agent Communication Helpers
# =============================================================================

# Notify next agent in pipeline
# Usage: notify_next_agent <current_agent> <signal_type> [payload_json]
notify_next_agent() {
    local current_agent="$1"
    local signal_type="$2"
    local payload="${3:-"{}"}"

    local next_agent
    next_agent=$(get_next_in_pipeline "$current_agent")

    if [[ -z "$next_agent" ]]; then
        echo "No next agent in pipeline for: ${current_agent}" >&2
        return 1
    fi

    # Process signal through orchestrator
    process_agent_signal "$current_agent" "$signal_type" "$payload"

    echo "Notified ${next_agent} of ${signal_type} from ${current_agent}"
}

# Get next agent in pipeline
get_next_in_pipeline() {
    local current="$1"

    case "$current" in
        developer) echo "tester" ;;
        tester) echo "reviewer" ;;
        reviewer) echo "" ;;  # End of pipeline
        *) echo "" ;;
    esac
}

# Get previous agent in pipeline
get_previous_in_pipeline() {
    local current="$1"

    case "$current" in
        developer) echo "" ;;  # Start of pipeline
        tester) echo "developer" ;;
        reviewer) echo "tester" ;;
        *) echo "" ;;
    esac
}

# =============================================================================
# Event Handlers
# =============================================================================

# Handle developer completion
# Usage: on_developer_complete <feature_name> <files_json> [notes]
on_developer_complete() {
    local feature="$1"
    local files="$2"
    local notes="${3:-}"

    echo "📦 Developer completed: ${feature}"

    # Update task status
    local tasks
    tasks=$(cat "${SWARM_DIR}/state/tasks.json" 2>/dev/null || echo "[]")
    local task_id
    task_id=$(echo "$tasks" | jq -r '[.[] | select(.agent == "developer" and .status == "in_progress")][0].id // empty')

    if [[ -n "$task_id" ]]; then
        update_task_status "$task_id" "completed" "{\"feature\": \"$feature\"}"
    fi

    # Notify tester
    process_agent_signal "developer" "feature_complete" \
        "$(jq -n --arg f "$feature" --argjson files "$files" --arg notes "$notes" \
        '{feature: $f, files: $files, notes: $notes}')"
}

# Handle tester completion
# Usage: on_tests_complete <passed|failed> <summary_json> [details_json]
on_tests_complete() {
    local status="$1"
    local summary="$2"
    local details="${3:-"{}"}"

    if [[ "$status" == "passed" ]]; then
        echo "✅ Tests passed!"
        process_agent_signal "tester" "tests_passed" \
            "$(jq -n --argjson s "$summary" '{summary: $s}')"
    else
        echo "❌ Tests failed!"
        process_agent_signal "tester" "tests_failed" \
            "$(jq -n --argjson s "$summary" --argjson d "$details" \
            '{summary: $s, details: $d}')"
    fi
}

# Merge a PR
# Usage: merge_pr <pr_url_or_number> [merge_method]
# merge_method: merge, squash, rebase (default: squash)
merge_pr() {
    local pr="$1"
    local merge_method="${2:-squash}"

    if [[ -z "$pr" ]]; then
        echo "❌ No PR specified" >&2
        return 1
    fi

    if ! command -v gh &>/dev/null; then
        echo "❌ GitHub CLI not available" >&2
        return 1
    fi

    echo "🔀 Merging PR: $pr (method: $merge_method)..." >&2
    log_activity "Merging PR: $pr"

    # Wait for CI checks to pass (with timeout)
    local max_wait=300  # 5 minutes
    local waited=0
    local check_interval=10

    echo "⏳ Waiting for CI checks..." >&2
    while [[ $waited -lt $max_wait ]]; do
        local checks_json
        checks_json=$(gh pr checks "$pr" --json name,state 2>/dev/null || echo "[]")
        local total_checks pending_checks failed_checks success_checks
        total_checks=$(echo "$checks_json" | jq 'length' 2>/dev/null || echo "0")
        pending_checks=$(echo "$checks_json" | jq '[.[] | select(.state == "PENDING" or .state == "IN_PROGRESS")] | length' 2>/dev/null || echo "0")
        failed_checks=$(echo "$checks_json" | jq '[.[] | select(.state == "FAILURE" or .state == "ERROR")] | length' 2>/dev/null || echo "0")
        success_checks=$(echo "$checks_json" | jq '[.[] | select(.state == "SUCCESS")] | length' 2>/dev/null || echo "0")

        # No checks configured - proceed
        if [[ "$total_checks" -eq 0 ]]; then
            echo "✅ No CI checks configured, proceeding" >&2
            break
        fi

        # Any failures - abort
        if [[ "$failed_checks" -gt 0 ]]; then
            echo "❌ CI checks failed ($failed_checks failed), cannot merge" >&2
            log_activity "CI checks failed for PR"
            return 1
        fi

        # All passed - proceed
        if [[ "$pending_checks" -eq 0 && "$success_checks" -eq "$total_checks" ]]; then
            echo "✅ All CI checks passed ($success_checks/$total_checks)" >&2
            break
        fi

        # Still pending - wait
        echo "   Waiting... ${success_checks}/${total_checks} passed, ${pending_checks} pending (${waited}s/${max_wait}s)" >&2
        sleep $check_interval
        waited=$((waited + check_interval))
    done

    if [[ $waited -ge $max_wait ]]; then
        echo "⚠️  CI check timeout, attempting merge anyway..." >&2
    fi

    # Attempt merge
    if gh pr merge "$pr" --"$merge_method" --delete-branch 2>&1; then
        echo "✅ PR merged successfully!" >&2
        log_activity "PR merged successfully"
        return 0
    else
        echo "❌ Failed to merge PR" >&2
        log_activity "Failed to merge PR"
        return 1
    fi
}

# Handle reviewer decision
# Usage: on_review_complete <approved|changes_requested> <comments_json> [pr_number]
on_review_complete() {
    local decision="$1"
    local comments="$2"
    local pr_number="${3:-}"

    if [[ "$decision" == "approved" ]]; then
        echo "✅ Code approved!"

        if [[ "$AUTO_MERGE" == "true" && -n "$pr_number" ]]; then
            merge_pr "$pr_number" "squash"
        fi

        process_agent_signal "reviewer" "review_approved" \
            "$(jq -n --arg pr "$pr_number" --argjson c "$comments" \
            '{pr_number: $pr, comments: $c}')"
    else
        echo "📝 Changes requested"
        process_agent_signal "reviewer" "review_changes_requested" \
            "$(jq -n --argjson c "$comments" '{comments: $c}')"
    fi
}

# =============================================================================
# Coordination Modes
# =============================================================================

# Run in pipeline mode (sequential)
# Usage: run_pipeline <prompt> [agents] [max_runs]
run_pipeline() {
    local prompt="$1"
    local agents="${2:-planner developer tester reviewer}"
    local max_runs="${3:-5}"

    echo "🔄 Running in PIPELINE mode"
    echo "   Flow: ${agents// / → }"
    echo ""

    # Execute agents in sequence
    run_agent_pipeline "$prompt" "$agents" "$max_runs"
}

# Run in parallel mode
# NOTE: True parallel execution requires worktree isolation (future feature)
# Currently runs as optimized sequential: planner → developer → tester → PR → reviewer
# Usage: run_parallel <prompt> [agents] [max_runs]
run_parallel() {
    local prompt="$1"
    local agents="${2:-planner developer tester reviewer}"
    local max_runs="${3:-5}"

    echo "⚡ Running in PARALLEL mode (optimized sequential)"
    echo "   Note: True parallel requires worktree isolation (future feature)"
    echo "   Current flow: planner → developer → tester → PR → reviewer"
    echo ""

    # For now, parallel mode uses the same pipeline logic
    # True parallel would need separate worktrees for each agent
    run_agent_pipeline "$prompt" "$agents" "$max_runs"
}

# Run in adaptive mode (dynamically adjust based on progress)
# Usage: run_adaptive <prompt> [agents] [max_runs]
run_adaptive() {
    local prompt="$1"
    local agents="${2:-planner developer tester reviewer}"
    local max_runs="${3:-5}"

    echo "🧠 Running in ADAPTIVE mode"
    echo "   Will adjust strategy based on progress"
    echo ""

    # Start as pipeline mode
    run_pipeline "$prompt" "$agents" "$max_runs"
}

# =============================================================================
# Status and Monitoring
# =============================================================================

# Get comprehensive coordination status
get_coordination_status() {
    local swarm_status
    swarm_status=$(get_swarm_status_json)

    local conflicts
    conflicts=$(detect_all_conflicts)

    local worktrees
    worktrees=$(get_worktrees_json)

    jq -n \
        --argjson swarm "$swarm_status" \
        --argjson conflicts "$conflicts" \
        --argjson worktrees "$worktrees" \
        --arg mode "$COORDINATION_MODE" \
        --arg auto_merge "$AUTO_MERGE" \
        '{
            mode: $mode,
            auto_merge: ($auto_merge == "true"),
            swarm: $swarm,
            conflicts: $conflicts,
            worktrees: $worktrees
        }'
}

# Print coordination dashboard
# Print a compact status line (for real-time updates during execution)
# Usage: print_status_line <agent_id> <status> [extra_info]
print_status_line() {
    local agent_id="$1"
    local status="$2"
    local extra="${3:-}"
    local timestamp
    timestamp=$(date +"%H:%M:%S")

    local emoji
    case "$agent_id" in
        planner) emoji="📋" ;;
        developer) emoji="🧑‍💻" ;;
        tester) emoji="🧪" ;;
        reviewer) emoji="👁️" ;;
        *) emoji="🤖" ;;
    esac

    local status_icon
    case "$status" in
        running) status_icon="🟢" ;;
        waiting) status_icon="🟡" ;;
        complete) status_icon="✅" ;;
        error) status_icon="❌" ;;
        *) status_icon="⚪" ;;
    esac

    if [[ -n "$extra" ]]; then
        printf "[%s] %s %s %-10s %s %s\n" "$timestamp" "$status_icon" "$emoji" "$agent_id" "$status" "$extra"
    else
        printf "[%s] %s %s %-10s %s\n" "$timestamp" "$status_icon" "$emoji" "$agent_id" "$status"
    fi
}

# Print pipeline progress bar
# Usage: print_pipeline_progress <current_phase> <review_cycle> <bug_cycle>
print_pipeline_progress() {
    local current_phase="$1"
    local review_cycle="${2:-1}"
    local bug_cycle="${3:-1}"

    echo ""
    echo "┌─────────────────────────────────────────────────────────────────┐"

    local plan_icon dev_icon test_icon review_icon
    case "$current_phase" in
        planner)
            plan_icon="🔄" dev_icon="⏳" test_icon="⏳" review_icon="⏳" ;;
        developer)
            plan_icon="✅" dev_icon="🔄" test_icon="⏳" review_icon="⏳" ;;
        tester)
            plan_icon="✅" dev_icon="✅" test_icon="🔄" review_icon="⏳" ;;
        reviewer)
            plan_icon="✅" dev_icon="✅" test_icon="✅" review_icon="🔄" ;;
        complete)
            plan_icon="✅" dev_icon="✅" test_icon="✅" review_icon="✅" ;;
        *)
            plan_icon="⏳" dev_icon="⏳" test_icon="⏳" review_icon="⏳" ;;
    esac

    printf "│ %s Plan → %s Dev → %s Test → %s Review" "$plan_icon" "$dev_icon" "$test_icon" "$review_icon"
    if [[ $review_cycle -gt 1 ]]; then
        printf " (cycle %d)" "$review_cycle"
    fi
    printf "              │\n"

    if [[ $bug_cycle -gt 1 ]]; then
        printf "│ 🐛 Bug fix cycle: %d/3                                          │\n" "$bug_cycle"
    fi

    echo "└─────────────────────────────────────────────────────────────────┘"
}

print_coordination_dashboard() {
    # Don't clear screen if in verbose mode (to preserve streaming output)
    if [[ "$VERBOSE" != "true" ]]; then
        clear 2>/dev/null || true
    fi

    echo ""
    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            🐝 CONTINUOUS CLAUDE SWARM DASHBOARD               ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"

    local session
    session=$(get_session_state)
    local session_id
    session_id=$(echo "$session" | jq -r '.session_id // "N/A"')
    local status
    status=$(echo "$session" | jq -r '.status // "N/A"')
    local pr_url
    pr_url=$(echo "$session" | jq -r '.pr_url // ""')

    printf "║ Session: %-20s Mode: %-20s ║\n" "$session_id" "$COORDINATION_MODE"
    printf "║ Status: %-21s Auto-Merge: %-15s ║\n" "$status" "$AUTO_MERGE"
    if [[ -n "$pr_url" && "$pr_url" != "null" ]]; then
        printf "║ PR: %-55s ║\n" "${pr_url:0:55}"
    fi
    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Agent Status
    echo "║                         AGENTS                                ║"
    echo "╟───────────────────────────────────────────────────────────────╢"

    local agents_state
    agents_state=$(get_all_agents_state)

    for agent_id in $(echo "$agents_state" | jq -r 'keys[]' 2>/dev/null | sort); do
        local agent_status emoji iteration
        agent_status=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].status // "?"')
        emoji=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].emoji // "?"')
        iteration=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].iteration // 0')

        local status_icon
        case "$agent_status" in
            running) status_icon="🟢" ;;
            waiting) status_icon="🟡" ;;
            registered) status_icon="⚪" ;;
            stopped) status_icon="🔴" ;;
            complete) status_icon="✅" ;;
            *) status_icon="⚫" ;;
        esac

        printf "║ %s %s %-10s  %-15s  Iterations: %-3s           ║\n" \
            "$status_icon" "$emoji" "$agent_id" "$agent_status" "$iteration"
    done

    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Task Queue
    local task_summary
    task_summary=$(get_task_queue_summary)
    local pending in_progress completed failed
    pending=$(echo "$task_summary" | jq -r '.pending // 0')
    in_progress=$(echo "$task_summary" | jq -r '.in_progress // 0')
    completed=$(echo "$task_summary" | jq -r '.completed // 0')
    failed=$(echo "$task_summary" | jq -r '.failed // 0')

    echo "║                       TASK QUEUE                              ║"
    echo "╟───────────────────────────────────────────────────────────────╢"
    printf "║   ⏳ Pending: %-5s  🔄 In Progress: %-5s                    ║\n" "$pending" "$in_progress"
    printf "║   ✅ Done: %-8s  ❌ Failed: %-8s                       ║\n" "$completed" "$failed"

    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Recent Activity (last 3 log entries)
    echo "║                     RECENT ACTIVITY                           ║"
    echo "╟───────────────────────────────────────────────────────────────╢"

    local state_dir=".continuous-claude/state"
    if [[ -f "${state_dir}/activity.log" ]]; then
        tail -3 "${state_dir}/activity.log" 2>/dev/null | while read -r line; do
            printf "║   %-59s ║\n" "${line:0:59}"
        done
    else
        echo "║   No recent activity                                          ║"
    fi

    echo "╚═══════════════════════════════════════════════════════════════╝"
}

# Log activity for dashboard
# Usage: log_activity <message>
log_activity() {
    local message="$1"
    local state_dir=".continuous-claude/state"
    local timestamp
    timestamp=$(date +"%H:%M:%S")

    mkdir -p "$state_dir"
    echo "[${timestamp}] ${message}" >> "${state_dir}/activity.log"

    # Keep only last 50 lines
    if [[ -f "${state_dir}/activity.log" ]]; then
        tail -50 "${state_dir}/activity.log" > "${state_dir}/activity.log.tmp" 2>/dev/null
        mv "${state_dir}/activity.log.tmp" "${state_dir}/activity.log" 2>/dev/null
    fi
}

# =============================================================================
# Agent Execution
# =============================================================================

# Completion signals
AGENT_TASK_COMPLETE="AGENT_TASK_COMPLETE"
PROJECT_COMPLETE="CONTINUOUS_CLAUDE_PROJECT_COMPLETE"

# Reviewer signals
REVIEW_APPROVED="REVIEW_APPROVED"
REVIEW_CHANGES_REQUESTED="REVIEW_CHANGES_REQUESTED"

# Run a single agent iteration with Claude Code
# Usage: execute_agent <agent_id> <prompt> [max_runs]
# Returns: 0 on success, 1 on failure, 2 if bugs found (tester), 3 if changes requested (reviewer)
execute_agent() {
    local agent_id="$1"
    local prompt="$2"
    local max_runs="${3:-5}"
    local notes_file="SHARED_TASK_NOTES.md"

    echo "🤖 [${agent_id}] Starting agent execution... (verbose=${VERBOSE:-not set})"
    log_activity "[${agent_id}] Starting execution"

    # Update agent state
    update_agent_state "$agent_id" "running"

    # Track commits before agent runs
    local commits_before
    commits_before=$(git rev-list --count HEAD 2>/dev/null || echo "0")

    # Run Claude Code iterations
    local iteration=0
    local agent_result=0
    while [[ $iteration -lt $max_runs ]]; do
        iteration=$((iteration + 1))
        increment_iteration "$agent_id"

        echo "🔄 [${agent_id}] Iteration ${iteration}/${max_runs}"
        log_activity "[${agent_id}] Iteration ${iteration}/${max_runs}"

        # Build the full prompt with notes context
        local full_prompt
        full_prompt=$(build_full_prompt "$agent_id" "$prompt" "$notes_file")

        # Run claude with JSON output format
        local temp_stdout=$(mktemp)
        local temp_stderr=$(mktemp)
        local exit_code=0

        if [[ "$VERBOSE" == "true" ]]; then
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📺 [${agent_id}] Live output:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            # Run claude and display output in real-time using tee
            claude --dangerously-skip-permissions -p "$full_prompt" 2>&1 | tee "$temp_stdout"
            exit_code=${PIPESTATUS[0]}
            cp "$temp_stdout" "$temp_stderr" 2>/dev/null || true
            echo ""
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        else
            claude --dangerously-skip-permissions --output-format json -p "$full_prompt" >"$temp_stdout" 2>"$temp_stderr" || exit_code=$?
        fi

        if [[ $exit_code -eq 0 ]]; then
            echo "✅ [${agent_id}] Iteration ${iteration} complete"

            # Parse cost from JSON output (only available in non-verbose mode)
            if [[ "$VERBOSE" != "true" ]]; then
                local cost
                cost=$(cat "$temp_stdout" | jq -r 'if type == "array" then .[-1] else . end | .cost_usd // .total_cost // 0' 2>/dev/null || echo "0")
                if [[ "$cost" != "0" && "$cost" != "null" ]]; then
                    echo "   💰 Cost: \$${cost}"
                fi

                # Show output summary in non-verbose mode
                if [[ -s "$temp_stderr" ]]; then
                    echo "   📝 Output (last 5 lines):"
                    tail -5 "$temp_stderr" | sed 's/^/      /'
                fi
            fi
        else
            echo "❌ [${agent_id}] Iteration ${iteration} failed (exit code: ${exit_code})"
            if [[ -s "$temp_stderr" ]]; then
                tail -10 "$temp_stderr"
            fi
        fi

        # Check for task completion signal (agent finished its work)
        if grep -q "$AGENT_TASK_COMPLETE" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
            echo "✅ [${agent_id}] Agent completed its task"
            log_activity "[${agent_id}] Task completed"
            rm -f "$temp_stdout" "$temp_stderr"
            break
        fi

        # Check for project completion signal
        if grep -q "$PROJECT_COMPLETE" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
            echo "🎉 [${agent_id}] Project complete signal detected"
            log_activity "[${agent_id}] Project complete"
            rm -f "$temp_stdout" "$temp_stderr"
            break
        fi

        # Check if tester found bugs (special handling)
        if [[ "$agent_id" == "tester" ]]; then
            if grep -q "BUGS_FOUND" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
                echo "🐛 [${agent_id}] Bugs found - will need developer fix"
                log_activity "[${agent_id}] Bugs found"
                agent_result=2
                rm -f "$temp_stdout" "$temp_stderr"
                break
            fi
        fi

        # Check reviewer decision (special handling)
        if [[ "$agent_id" == "reviewer" ]]; then
            if grep -q "$REVIEW_CHANGES_REQUESTED" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
                echo "📝 [${agent_id}] Changes requested - will need developer fix"
                log_activity "[${agent_id}] Requested changes"
                agent_result=3
                rm -f "$temp_stdout" "$temp_stderr"
                break
            elif grep -q "$REVIEW_APPROVED" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
                echo "✅ [${agent_id}] PR approved for merge"
                log_activity "[${agent_id}] Approved PR"
                agent_result=0
                rm -f "$temp_stdout" "$temp_stderr"
                break
            fi
        fi

        rm -f "$temp_stdout" "$temp_stderr"
        sleep 1
    done

    # Verify commits were made (for developer)
    if [[ "$agent_id" == "developer" ]]; then
        local commits_after
        commits_after=$(git rev-list --count HEAD 2>/dev/null || echo "0")
        if [[ "$commits_after" -eq "$commits_before" ]]; then
            echo "⚠️  [${agent_id}] Warning: No commits were made"
        else
            local new_commits=$((commits_after - commits_before))
            echo "📝 [${agent_id}] Made ${new_commits} commit(s)"
        fi
    fi

    update_agent_state "$agent_id" "completed"
    echo "✅ [${agent_id}] Agent finished after ${iteration} iterations"
    return $agent_result
}

# Build complete prompt with notes context
# Usage: build_full_prompt <agent_id> <task_prompt> <notes_file>
build_full_prompt() {
    local agent_id="$1"
    local task_prompt="$2"
    local notes_file="$3"

    local full_prompt="$task_prompt"

    # Add notes context if file exists
    if [[ -f "$notes_file" ]]; then
        full_prompt+="

## CURRENT STATUS (from ${notes_file})

$(cat "$notes_file")"
    fi

    # Add critical instructions
    local agent_emoji=""
    case "$agent_id" in
        planner) agent_emoji="📋" ;;
        developer) agent_emoji="🧑‍💻" ;;
        tester) agent_emoji="🧪" ;;
        reviewer) agent_emoji="👁️" ;;
        *) agent_emoji="🤖" ;;
    esac

    full_prompt+="

## CRITICAL INSTRUCTIONS
- DO NOT ask questions. Proceed with reasonable defaults.
- DO NOT wait for confirmation. Just do the work.
- When your task is complete, include '${AGENT_TASK_COMPLETE}' in your response.
- Update ${notes_file} with your progress and any important notes for the next agent.

## COMMIT MESSAGE FORMAT
When committing changes, use this format:
\`\`\`
${agent_emoji} [${agent_id}] <short description>

<detailed description if needed>
\`\`\`

Example: '${agent_emoji} [${agent_id}] Add user authentication module'"

    echo "$full_prompt"
}

# Run agents in sequence (pipeline)
# Workflow: planner → developer → tester → (loop if bugs) → reviewer → (loop if changes requested) → PR ready
# Usage: run_agent_pipeline <prompt> <agents> [max_runs]
run_agent_pipeline() {
    local prompt="$1"
    local agents="$2"
    local max_runs="${3:-5}"
    local notes_file="SHARED_TASK_NOTES.md"
    local max_bug_fix_cycles=3
    local max_review_cycles=3

    # Create a working branch for the swarm
    local branch_name
    branch_name=$(create_swarm_branch)
    if [[ -z "$branch_name" ]]; then
        echo "⚠️  Not in a git repo, continuing without branch"
    fi

    # Create Draft PR immediately (PR updates as agents push commits)
    local pr_url=""
    if [[ -n "$branch_name" ]]; then
        pr_url=$(create_draft_pr "$branch_name" "$prompt")
        if [[ -n "$pr_url" ]]; then
            echo ""
            echo "📋 PR URL: ${pr_url} (Draft)"
            echo "   (PR will be marked Ready when reviewer approves)"
            echo ""
        fi
    fi

    # Phase 1: Planning
    if [[ "$agents" == *"planner"* ]]; then
        run_agent_phase "planner" "$prompt" "$max_runs" "Phase 1: Planning"
        push_agent_changes "planner"
    fi

    # Main Development → Test → Review Loop
    local review_cycle=0
    local changes_requested=true
    local review_approved=false

    while [[ "$changes_requested" == "true" && $review_cycle -lt $max_review_cycles ]]; do
        review_cycle=$((review_cycle + 1))

        if [[ $review_cycle -gt 1 ]]; then
            echo ""
            echo "╔═══════════════════════════════════════════════════════════════╗"
            echo "║  🔄 Review Feedback Cycle ${review_cycle}/${max_review_cycles}                               ║"
            echo "╚═══════════════════════════════════════════════════════════════╝"
        fi

        # Phase 2: Development & Testing Loop (inner loop for bugs)
        local bug_fix_cycle=0
        local bugs_found=true

        while [[ "$bugs_found" == "true" && $bug_fix_cycle -lt $max_bug_fix_cycles ]]; do
            bug_fix_cycle=$((bug_fix_cycle + 1))

            if [[ $bug_fix_cycle -gt 1 ]]; then
                echo ""
                echo "🔁 Bug fix cycle ${bug_fix_cycle}/${max_bug_fix_cycles}"
            fi

            # Developer phase
            if [[ "$agents" == *"developer"* ]]; then
                local phase_label="Phase 2: Development"
                if [[ $review_cycle -gt 1 ]]; then
                    phase_label="Phase 2: Development (addressing review feedback)"
                fi
                run_agent_phase "developer" "$prompt" "$max_runs" "$phase_label"
                push_agent_changes "developer"
            fi

            # Tester phase
            if [[ "$agents" == *"tester"* ]]; then
                run_agent_phase "tester" "$prompt" "$max_runs" "Phase 3: Testing"
                local tester_result=$?
                push_agent_changes "tester"

                if [[ $tester_result -eq 2 ]]; then
                    echo "🐛 Bugs found, cycling back to developer..."
                    bugs_found=true
                else
                    bugs_found=false
                fi
            else
                bugs_found=false
            fi
        done

        if [[ $bug_fix_cycle -ge $max_bug_fix_cycles && "$bugs_found" == "true" ]]; then
            echo "⚠️  Max bug fix cycles reached, proceeding to review anyway"
        fi

        # Phase 4: Review (reviewer decides if approved or changes needed)
        if [[ "$agents" == *"reviewer"* ]]; then
            # Note: run_agent_phase will use SWARM_PR_URL for reviewer prompt
            run_agent_phase "reviewer" "$prompt" "$max_runs" "Phase 4: Code Review"
            local reviewer_result=$?
            push_agent_changes "reviewer"

            if [[ $reviewer_result -eq 3 ]]; then
                echo ""
                echo "📝 Reviewer requested changes - cycling back to developer..."
                changes_requested=true
            else
                echo ""
                echo "✅ Reviewer approved the changes!"
                changes_requested=false
                review_approved=true
            fi
        else
            changes_requested=false
            review_approved=true
        fi
    done

    if [[ $review_cycle -ge $max_review_cycles && "$changes_requested" == "true" ]]; then
        echo "⚠️  Max review cycles reached, proceeding to finalize"
    fi

    # Mark PR ready for review ONLY after reviewer approves
    if [[ -n "$pr_url" && "$review_approved" == "true" ]]; then
        mark_pr_ready_for_review "$pr_url" "$prompt"

        # Auto merge if enabled
        if [[ "$AUTO_MERGE" == "true" ]]; then
            echo ""
            echo "═══════════════════════════════════════════════════════════════"
            echo "  Phase 5: Auto Merge"
            echo "═══════════════════════════════════════════════════════════════"
            log_activity "Starting auto merge"

            if merge_pr "$pr_url" "squash"; then
                echo ""
                echo "🎉 Pipeline completed successfully! PR merged."
                log_activity "Pipeline completed - PR merged"
                return 0
            else
                echo ""
                echo "⚠️  Pipeline completed but merge failed. PR is ready for manual merge."
                log_activity "Pipeline completed - merge failed"
            fi
        fi
    fi

    echo ""
    if [[ "$review_approved" == "true" ]]; then
        echo "🎉 Pipeline completed successfully!"
    else
        echo "⚠️  Pipeline completed (review not fully approved)"
    fi
    if [[ -n "$pr_url" ]]; then
        echo "📋 PR: ${pr_url}"
    fi
}

# Run a single agent phase with nice output
# Usage: run_agent_phase <agent_id> <prompt> <max_runs> <phase_name>
run_agent_phase() {
    local agent_id="$1"
    local prompt="$2"
    local max_runs="$3"
    local phase_name="$4"

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  ${phase_name}: ${agent_id}"
    echo "═══════════════════════════════════════════════════════════════"

    # Log activity
    log_activity "${phase_name} started"

    # Build agent prompt (use SWARM_PR_URL for reviewer)
    local agent_prompt
    if [[ "$agent_id" == "reviewer" ]]; then
        agent_prompt=$(build_agent_prompt "$agent_id" "$prompt" "${SWARM_PR_URL:-}")
    else
        agent_prompt=$(build_agent_prompt "$agent_id" "$prompt")
    fi

    execute_agent "$agent_id" "$agent_prompt" "$max_runs"
    local result=$?

    # Log completion
    if [[ $result -eq 0 ]]; then
        log_activity "${phase_name} completed"
    elif [[ $result -eq 2 ]]; then
        log_activity "${phase_name} found bugs"
    elif [[ $result -eq 3 ]]; then
        log_activity "${phase_name} requested changes"
    else
        log_activity "${phase_name} failed"
    fi

    print_coordination_dashboard
    return $result
}

# Create swarm branch with error handling
# Usage: create_swarm_branch
# Returns: branch name or empty string
create_swarm_branch() {
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        return 0
    fi

    local branch_name="continuous-claude/swarm-${SWARM_SESSION_ID}"
    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    main_branch="${main_branch:-main}"

    echo "🌿 Creating swarm branch: ${branch_name}" >&2

    # Try to create new branch
    if git checkout -b "$branch_name" 2>/dev/null; then
        echo "$branch_name"
        return 0
    fi

    # Branch exists, try to checkout
    if git checkout "$branch_name" 2>/dev/null; then
        echo "$branch_name"
        return 0
    fi

    # Both failed
    echo "❌ Failed to create/checkout branch: ${branch_name}" >&2
    return 1
}

# Build role-specific prompt for each agent
# Usage: build_agent_prompt <agent_id> <base_prompt> [pr_url]
build_agent_prompt() {
    local agent_id="$1"
    local base_prompt="$2"
    local pr_url="${3:-}"
    local notes_file="SHARED_TASK_NOTES.md"

    case "$agent_id" in
        planner)
            cat << EOF
# 📋 PLANNER AGENT TASK

## Your Mission
Analyze the following request and create a detailed, actionable implementation plan.

## Request
${base_prompt}

## Deliverables
Create ${notes_file} with:

1. **Task Breakdown**: List specific implementation steps
2. **Files to Modify**: Which files need to be created/changed
3. **Acceptance Criteria**: How to verify each step is complete
4. **Dependencies**: Any prerequisites or considerations

## Output Format in ${notes_file}
\`\`\`markdown
# Implementation Plan

## Overview
Brief description of what will be built

## Steps
1. [ ] Step 1: Description
   - Files: file1.ts, file2.ts
   - Criteria: How to verify

2. [ ] Step 2: Description
   ...

## Notes for Developer
Any important considerations
\`\`\`

When done, include 'AGENT_TASK_COMPLETE' in your response.
EOF
            ;;
        developer)
            cat << EOF
# 🧑‍💻 DEVELOPER AGENT TASK

## Your Mission
Implement the feature/fix following the plan in ${notes_file}.

## Original Request
${base_prompt}

## Instructions
1. **Read the Plan**: Check ${notes_file} for implementation steps
2. **Implement Step by Step**: Follow the plan's task breakdown
3. **Commit Changes**: Make atomic commits with clear messages
4. **Update Notes**: Mark completed steps in ${notes_file}

## Important Rules
- DO NOT write tests (Tester agent handles this)
- DO NOT skip steps from the plan
- Commit after each logical change
- If blocked, document the issue in ${notes_file}

## When Done
Update ${notes_file} with:
- Which steps you completed
- Any issues encountered
- Notes for the Tester

Include 'AGENT_TASK_COMPLETE' in your response.
EOF
            ;;
        tester)
            cat << EOF
# 🧪 TESTER AGENT TASK

## Your Mission
Write and run tests for the implementation documented in ${notes_file}.

## Original Request
${base_prompt}

## Instructions
1. **Read Notes**: Check ${notes_file} for what was implemented
2. **Write Tests**: Create comprehensive test coverage
3. **Run Tests**: Execute all tests and verify they pass
4. **Document Results**: Update ${notes_file} with test status

## Test Requirements
- Unit tests for new functions/methods
- Integration tests if applicable
- Edge case coverage
- Error handling tests

## Important Rules
- DO NOT fix implementation bugs
- If tests fail, document failures in ${notes_file} and include 'BUGS_FOUND' in your response
- If all tests pass, include 'AGENT_TASK_COMPLETE'

## Output to ${notes_file}
\`\`\`markdown
## Test Results
- Tests written: X
- Tests passing: Y
- Coverage: Z%

### Issues Found (if any)
- Bug 1: Description
- Bug 2: Description
\`\`\`
EOF
            ;;
        reviewer)
            local pr_section=""
            local pr_commands=""
            if [[ -n "$pr_url" ]]; then
                pr_section="
## Pull Request to Review
**URL:** ${pr_url}

This PR has been created and updated by the previous agents (planner, developer, tester).
"
                pr_commands="
## Useful Commands
\`\`\`bash
# View PR details
gh pr view ${pr_url}

# View code changes
gh pr diff ${pr_url}

# Approve the PR (when satisfied)
gh pr review ${pr_url} --approve

# Request changes
gh pr review ${pr_url} --request-changes --body 'Your feedback here'
\`\`\`
"
            fi
            cat << EOF
# 👁️ REVIEWER AGENT TASK

## Your Mission
Review the code changes in the Pull Request and either approve or request changes.
${pr_section}
## Original Request
${base_prompt}
${pr_commands}
## Review Checklist
1. **Code Quality**: Clean, readable, follows best practices
2. **Security**: No vulnerabilities, proper input validation
3. **Tests**: Adequate coverage, tests are meaningful
4. **Documentation**: Code is well-commented where needed
5. **Acceptance Criteria**: All requirements from plan are met

## Instructions
1. Read ${notes_file} for context of what was implemented
2. Use 'gh pr diff' to review the actual code changes
3. Check test results from tester notes
4. Either APPROVE or REQUEST CHANGES using gh pr review

## Output to ${notes_file}
\`\`\`markdown
## Code Review Summary

### Verdict: APPROVED / CHANGES_REQUESTED

### Feedback
- Issue 1: Description (severity: high/medium/low)
- Issue 2: Description

### What's Good
- Positive point 1
- Positive point 2
\`\`\`

## Final Actions
- If approved: Run 'gh pr review --approve' and include 'REVIEW_APPROVED' and 'AGENT_TASK_COMPLETE' in your response
- If changes needed: Run 'gh pr review --request-changes --body "..."' and include 'REVIEW_CHANGES_REQUESTED' in your response
  - Clearly describe what needs to be fixed in ${notes_file}
  - The developer will receive your feedback and make corrections

**IMPORTANT:** You MUST include exactly one of these signals in your response:
- 'REVIEW_APPROVED' - when the code is ready to merge
- 'REVIEW_CHANGES_REQUESTED' - when the developer needs to make changes
EOF
            ;;
        *)
            echo "${base_prompt}"
            ;;
    esac
}

# Create a Draft PR at the start of the swarm
# Usage: create_draft_pr <branch_name> <prompt>
# Returns: PR URL (echoed to stdout)
create_draft_pr() {
    local branch_name="$1"
    local prompt="$2"
    local notes_file="SHARED_TASK_NOTES.md"

    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    main_branch="${main_branch:-main}"

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  Creating Draft Pull Request" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2

    # Create initial commit for PR (always create/update notes file)
    cat > "$notes_file" << EOF
# Swarm Task Notes

> Session: ${SWARM_SESSION_ID}

## Task
${prompt}

## Status: In Progress

Agents are working on this task...
EOF
    git add "$notes_file" >/dev/null 2>&1
    git commit -m "🚀 [swarm] Initialize task

Session: ${SWARM_SESSION_ID}
Task: ${prompt:0:60}" >/dev/null 2>&1 || true

    # Push the branch
    echo "📤 Pushing branch: ${branch_name}" >&2
    local push_output
    if ! push_output=$(git push -u origin "$branch_name" 2>&1); then
        echo "⚠️  Failed to push branch" >&2
        echo "$push_output" >&2
        return 1
    fi

    # Build PR body
    local pr_body="## 🚧 Work In Progress

This PR is being worked on by Continuous Claude Swarm.

**Task:** ${prompt}

**Session:** \`${SWARM_SESSION_ID}\`

---

### Progress

| Phase | Agent | Status |
|-------|-------|--------|
| Planning | 📋 Planner | ⏳ Pending |
| Development | 🧑‍💻 Developer | ⏳ Pending |
| Testing | 🧪 Tester | ⏳ Pending |
| Review | 👁️ Reviewer | ⏳ Pending |

---
🤖 Generated with [Continuous Claude](https://github.com/primadonna-gpters/continuous-claude)"

    # Create Draft PR using gh CLI
    if command -v gh &>/dev/null; then
        echo "📝 Creating draft PR..." >&2
        local pr_url
        local pr_error
        pr_error=$(mktemp)

        pr_url=$(gh pr create \
            --title "🚧 [WIP] ${prompt:0:50}" \
            --body "$pr_body" \
            --base "$main_branch" \
            --head "$branch_name" \
            --draft 2>"$pr_error")

        if [[ -n "$pr_url" ]]; then
            echo "✅ Draft PR created: ${pr_url}" >&2
            export SWARM_PR_URL="$pr_url"
            rm -f "$pr_error"
            echo "$pr_url"
            return 0
        else
            echo "⚠️  Failed to create PR:" >&2
            cat "$pr_error" >&2
            rm -f "$pr_error"

            # Check if PR already exists
            local existing_pr
            existing_pr=$(gh pr list --head "$branch_name" --json url --jq '.[0].url' 2>/dev/null)
            if [[ -n "$existing_pr" ]]; then
                echo "📋 Using existing PR: ${existing_pr}" >&2
                export SWARM_PR_URL="$existing_pr"
                echo "$existing_pr"
                return 0
            fi
            return 1
        fi
    else
        echo "⚠️  gh CLI not found. Please create PR manually:" >&2
        echo "   gh pr create --draft --base $main_branch --head $branch_name" >&2
        return 1
    fi
}

# Update PR progress after each agent completes
# Usage: update_pr_progress <completed_agent_id>
update_pr_progress() {
    local completed_agent="$1"
    local pr_url="${SWARM_PR_URL:-}"

    if [[ -z "$pr_url" ]]; then
        return 0  # No PR to update
    fi

    if ! command -v gh &>/dev/null; then
        return 0
    fi

    # Build progress table based on agent states
    local planner_status="⏳ Pending"
    local developer_status="⏳ Pending"
    local tester_status="⏳ Pending"
    local reviewer_status="⏳ Pending"

    # Get current agent states from state file
    local state_file=".continuous-claude/state/agents.json"
    if [[ -f "$state_file" ]]; then
        local get_status
        get_status() {
            local agent="$1"
            local status
            status=$(jq -r --arg a "$agent" '.[$a].status // "pending"' "$state_file" 2>/dev/null)
            case "$status" in
                completed|complete) echo "✅ Done" ;;
                running) echo "🔄 Running" ;;
                *) echo "⏳ Pending" ;;
            esac
        }
        planner_status=$(get_status "planner")
        developer_status=$(get_status "developer")
        tester_status=$(get_status "tester")
        reviewer_status=$(get_status "reviewer")
    fi

    # Mark the just-completed agent
    case "$completed_agent" in
        planner) planner_status="✅ Done" ;;
        developer) developer_status="✅ Done" ;;
        tester) tester_status="✅ Done" ;;
        reviewer) reviewer_status="✅ Done" ;;
    esac

    local pr_body="## 🚧 Work In Progress

This PR is being worked on by Continuous Claude Swarm.

**Session:** \`${SWARM_SESSION_ID}\`

---

### Progress

| Phase | Agent | Status |
|-------|-------|--------|
| Planning | 📋 Planner | ${planner_status} |
| Development | 🧑‍💻 Developer | ${developer_status} |
| Testing | 🧪 Tester | ${tester_status} |
| Review | 👁️ Reviewer | ${reviewer_status} |

---
🤖 Generated with [Continuous Claude](https://github.com/primadonna-gpters/continuous-claude)"

    # Update PR body silently
    gh pr edit "$pr_url" --body "$pr_body" >/dev/null 2>&1 || true
}

# Push agent changes after each phase
# Usage: push_agent_changes <agent_id>
push_agent_changes() {
    local agent_id="$1"

    # Check if there are changes to push
    if git diff --quiet HEAD @{u} 2>/dev/null; then
        # No changes to push, but still update PR progress
        update_pr_progress "$agent_id"
        return 0
    fi

    echo "📤 Pushing ${agent_id} changes..." >&2
    if git push 2>/dev/null; then
        echo "✅ Changes pushed" >&2
        # Update PR progress after successful push
        update_pr_progress "$agent_id"
        return 0
    else
        echo "⚠️  Failed to push changes" >&2
        return 1
    fi
}

# Mark PR as ready for review (remove draft status)
# Usage: mark_pr_ready_for_review <pr_url> <prompt>
mark_pr_ready_for_review() {
    local pr_url="$1"
    local prompt="$2"
    local notes_file="SHARED_TASK_NOTES.md"

    if [[ -z "$pr_url" ]]; then
        return 1
    fi

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  Marking PR Ready for Review" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2

    # Update PR title and body
    local pr_body="## Summary

This PR was created by Continuous Claude Swarm.

**Task:** ${prompt}

**Session:** \`${SWARM_SESSION_ID}\`
"
    if [[ -f "$notes_file" ]]; then
        pr_body+="
## Implementation Notes

<details>
<summary>Click to expand task notes</summary>

\`\`\`markdown
$(cat "$notes_file")
\`\`\`

</details>
"
    fi

    pr_body+="
---
🤖 Generated with [Continuous Claude](https://github.com/primadonna-gpters/continuous-claude)"

    # Mark as ready for review
    if command -v gh &>/dev/null; then
        gh pr ready "$pr_url" 2>/dev/null || true
        gh pr edit "$pr_url" \
            --title "🤖 ${prompt:0:60}" \
            --body "$pr_body" 2>/dev/null || true
        echo "✅ PR marked ready for review" >&2
        return 0
    fi

    return 1
}

# =============================================================================
# Swarm Runner
# =============================================================================

# Main entry point for running a swarm task
# Usage: run_swarm <prompt> [mode] [agents]
run_swarm() {
    local prompt="$1"
    local mode="${2:-$COORDINATION_MODE}"
    local agents="${3:-planner developer tester reviewer}"
    local max_runs="${4:-5}"

    export COORDINATION_MODE="$mode"
    # Always generate a unique session ID for swarm runs
    # Format: YYYYMMDD-HHMMSS-PID-RANDOM (e.g., 20251210-143025-12345-a1b2)
    export SWARM_SESSION_ID="$(date +%Y%m%d-%H%M%S)-$$-$(printf '%04x' $RANDOM)"

    echo "🚀 Starting Continuous Claude Swarm"
    echo "   Session: ${SWARM_SESSION_ID}"
    echo "   Mode: ${mode}"
    echo "   Agents: ${agents}"
    echo ""

    # Initialize swarm state
    init_swarm "$agents" "$prompt"

    case "$mode" in
        pipeline)
            run_pipeline "$prompt" "$agents" "$max_runs"
            ;;
        parallel)
            run_parallel "$prompt" "$agents" "$max_runs"
            ;;
        adaptive)
            run_adaptive "$prompt" "$agents" "$max_runs"
            ;;
        *)
            echo "Error: Unknown mode: ${mode}" >&2
            return 1
            ;;
    esac

    echo ""
    echo "🎉 Swarm completed!"
    print_coordination_dashboard
}

# =============================================================================
# CLI Interface
# =============================================================================

coordination_cli() {
    local cmd="${1:-help}"
    shift || true

    case "$cmd" in
        run)
            run_swarm "${1:-}" "${2:-pipeline}" "${3:-}"
            ;;
        status)
            get_coordination_status | jq .
            ;;
        dashboard)
            print_coordination_dashboard
            ;;
        on-dev-complete)
            on_developer_complete "${1:-}" "${2:-[]}" "${3:-}"
            ;;
        on-tests-complete)
            on_tests_complete "${1:-passed}" "${2:-"{}"}" "${3:-"{}"}"
            ;;
        on-review-complete)
            on_review_complete "${1:-approved}" "${2:-[]}" "${3:-}"
            ;;
        notify)
            notify_next_agent "${1:-}" "${2:-}" "${3:-"{}"}"
            ;;
        help|*)
            echo "Usage: coordination.sh <command> [args]"
            echo ""
            echo "Commands:"
            echo "  run <prompt> [mode] [agents]    Start a swarm task"
            echo "    Modes: pipeline, parallel, adaptive"
            echo ""
            echo "  status                          Get coordination status as JSON"
            echo "  dashboard                       Print coordination dashboard"
            echo ""
            echo "Event Handlers:"
            echo "  on-dev-complete <feature> <files_json> [notes]"
            echo "  on-tests-complete <passed|failed> <summary> [details]"
            echo "  on-review-complete <approved|changes_requested> <comments> [pr]"
            echo ""
            echo "  notify <agent> <signal> [payload]"
            echo ""
            echo "Environment Variables:"
            echo "  COORDINATION_MODE    Default mode (pipeline/parallel/adaptive)"
            echo "  AUTO_MERGE           Auto-merge on approval (true/false)"
            ;;
    esac
}

# Run CLI if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    coordination_cli "$@"
fi
