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
VERBOSE="${VERBOSE:-false}"  # Show real-time agent output

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

# Handle reviewer decision
# Usage: on_review_complete <approved|changes_requested> <comments_json> [pr_number]
on_review_complete() {
    local decision="$1"
    local comments="$2"
    local pr_number="${3:-}"

    if [[ "$decision" == "approved" ]]; then
        echo "✅ Code approved!"

        if [[ "$AUTO_MERGE" == "true" && -n "$pr_number" ]]; then
            echo "🔀 Auto-merging PR #${pr_number}..."
            # TODO: Implement actual merge
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

# Run in parallel mode (concurrent where possible)
# Usage: run_parallel <prompt> [agents] [max_runs]
run_parallel() {
    local prompt="$1"
    local agents="${2:-planner developer tester reviewer}"
    local max_runs="${3:-5}"
    local branch_name="continuous-claude/swarm-${SWARM_SESSION_ID}"

    echo "⚡ Running in PARALLEL mode"
    echo "   Flow: planner → (developer ∥ tester) → reviewer"
    echo ""

    # Create a working branch for the swarm
    if git rev-parse --git-dir > /dev/null 2>&1; then
        echo "🌿 Creating swarm branch: ${branch_name}"
        git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name" 2>/dev/null || true
    fi

    # 1. Planner runs first (others depend on the plan)
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Phase 1: Planning"
    echo "═══════════════════════════════════════════════════════════════"
    local planner_prompt
    planner_prompt=$(build_agent_prompt "planner" "$prompt")
    execute_agent "planner" "$planner_prompt" "$max_runs"

    # 2. Developer and tester run in parallel
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Phase 2: Development & Testing (parallel)"
    echo "═══════════════════════════════════════════════════════════════"

    local dev_prompt tester_prompt
    dev_prompt=$(build_agent_prompt "developer" "$prompt")
    tester_prompt=$(build_agent_prompt "tester" "$prompt")

    (execute_agent "developer" "$dev_prompt" "$max_runs") &
    local dev_pid=$!

    (execute_agent "tester" "$tester_prompt" "$max_runs") &
    local test_pid=$!

    # Wait for both to complete
    echo "⏳ Waiting for developer and tester to complete..."
    wait $dev_pid $test_pid

    # 3. Reviewer runs last
    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Phase 3: Review"
    echo "═══════════════════════════════════════════════════════════════"
    local reviewer_prompt
    reviewer_prompt=$(build_agent_prompt "reviewer" "$prompt")
    execute_agent "reviewer" "$reviewer_prompt" "$max_runs"

    # Create PR if we have changes
    if git rev-parse --git-dir > /dev/null 2>&1; then
        create_swarm_pr "$branch_name" "$prompt"
    fi
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
print_coordination_dashboard() {
    clear 2>/dev/null || true

    echo "╔═══════════════════════════════════════════════════════════════╗"
    echo "║            🐝 CONTINUOUS CLAUDE SWARM DASHBOARD               ║"
    echo "╠═══════════════════════════════════════════════════════════════╣"

    local session
    session=$(get_session_state)
    local session_id
    session_id=$(echo "$session" | jq -r '.session_id // "N/A"')
    local status
    status=$(echo "$session" | jq -r '.status // "N/A"')

    printf "║ Session: %-20s Mode: %-20s ║\n" "$session_id" "$COORDINATION_MODE"
    printf "║ Status: %-21s Auto-Merge: %-15s ║\n" "$status" "$AUTO_MERGE"
    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Agent Status
    echo "║                         AGENTS                                ║"
    echo "╟───────────────────────────────────────────────────────────────╢"

    local agents_state
    agents_state=$(get_all_agents_state)

    for agent_id in $(echo "$agents_state" | jq -r 'keys[]' | sort); do
        local agent_status emoji iteration unread
        agent_status=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].status // "?"')
        emoji=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].emoji // "?"')
        iteration=$(echo "$agents_state" | jq -r --arg id "$agent_id" '.[$id].iteration // 0')
        unread=$(get_unread_count "$agent_id")

        local status_icon
        case "$agent_status" in
            running) status_icon="🟢" ;;
            waiting) status_icon="🟡" ;;
            registered) status_icon="⚪" ;;
            stopped) status_icon="🔴" ;;
            *) status_icon="⚫" ;;
        esac

        printf "║ %s %s %-10s  %s %-12s  Iter: %-3s  📬 %-3s        ║\n" \
            "$status_icon" "$emoji" "$agent_id" " " "$agent_status" "$iteration" "$unread"
    done

    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Task Queue
    local task_summary
    task_summary=$(get_task_queue_summary)
    local pending in_progress completed failed
    pending=$(echo "$task_summary" | jq -r '.pending')
    in_progress=$(echo "$task_summary" | jq -r '.in_progress')
    completed=$(echo "$task_summary" | jq -r '.completed')
    failed=$(echo "$task_summary" | jq -r '.failed')

    echo "║                       TASK QUEUE                              ║"
    echo "╟───────────────────────────────────────────────────────────────╢"
    printf "║   ⏳ Pending: %-5s  🔄 In Progress: %-5s                    ║\n" "$pending" "$in_progress"
    printf "║   ✅ Done: %-8s  ❌ Failed: %-8s                       ║\n" "$completed" "$failed"

    echo "╠═══════════════════════════════════════════════════════════════╣"

    # Conflicts
    local conflicts
    conflicts=$(detect_all_conflicts)
    local conflict_count
    conflict_count=$(echo "$conflicts" | jq 'length')

    echo "║                      CONFLICTS                                ║"
    echo "╟───────────────────────────────────────────────────────────────╢"

    if [[ "$conflict_count" -gt 0 ]]; then
        echo "$conflicts" | jq -r '.[] | "║   ⚠️  \(.agents | join(" vs ")) on \(.files | join(", "))"' | head -3
    else
        echo "║   ✅ No conflicts detected                                    ║"
    fi

    echo "╚═══════════════════════════════════════════════════════════════╝"
}

# =============================================================================
# Agent Execution
# =============================================================================

# Run a single agent iteration with Claude Code
# Usage: execute_agent <agent_id> <prompt> [max_runs]
execute_agent() {
    local agent_id="$1"
    local prompt="$2"
    local max_runs="${3:-5}"
    local notes_file="SHARED_TASK_NOTES.md"
    local completion_signal="CONTINUOUS_CLAUDE_PROJECT_COMPLETE"

    # Get persona prompt
    local persona_prompt
    persona_prompt=$(get_persona_prompt "$agent_id" 2>/dev/null || echo "")

    echo "🤖 [${agent_id}] Starting agent execution..."

    # Update agent state
    update_agent_state "$agent_id" "running"

    # Run Claude Code iterations
    local iteration=0
    while [[ $iteration -lt $max_runs ]]; do
        iteration=$((iteration + 1))
        increment_iteration "$agent_id"

        echo "🔄 [${agent_id}] Iteration ${iteration}/${max_runs}"

        # Build full prompt (similar to single mode)
        local full_prompt="## CONTINUOUS WORKFLOW CONTEXT

This is part of a continuous development loop where work happens incrementally across multiple iterations.

**Important**: You don't need to complete the entire goal in one iteration. Just make meaningful progress on one thing, then leave clear notes for the next iteration.

**Project Completion Signal**: If you determine that the ENTIRE project goal is fully complete, include the exact phrase \"${completion_signal}\" in your response."

        # Add persona role if available
        if [[ -n "$persona_prompt" ]]; then
            full_prompt+="

## AGENT ROLE (${agent_id})
${persona_prompt}"
        fi

        # Add primary goal
        full_prompt+="

## PRIMARY GOAL
${prompt}"

        # Add context from previous iterations if notes file exists
        if [[ -f "$notes_file" ]]; then
            local notes_content
            notes_content=$(cat "$notes_file")
            full_prompt+="

## CONTEXT FROM PREVIOUS ITERATION

The following is from ${notes_file}, maintained by previous iterations to provide context:

${notes_content}"
        fi

        # Add iteration notes instructions
        full_prompt+="

## ITERATION NOTES

"
        if [[ -f "$notes_file" ]]; then
            full_prompt+="Update the \`${notes_file}\` file with relevant context for the next iteration. Add new notes and remove outdated information to keep it current and useful."
        else
            full_prompt+="Create a \`${notes_file}\` file with relevant context and instructions for the next iteration."
        fi

        full_prompt+="

This file helps coordinate work across iterations. It should:
- Contain relevant context and instructions for the next iteration
- Stay concise and actionable (like a notes file, not a detailed report)
- Help the next developer understand what to do next

## CRITICAL INSTRUCTIONS
- DO NOT ask questions. Proceed with reasonable defaults.
- DO NOT wait for confirmation. Just do the work.
- Focus on your specific role as ${agent_id}
- Make meaningful progress on the task
- Update ${notes_file} with what you accomplished"

        # Run claude with JSON output format (like single mode)
        local temp_stdout=$(mktemp)
        local temp_stderr=$(mktemp)
        local exit_code=0

        if [[ "$VERBOSE" == "true" ]]; then
            # Verbose mode: stream output in real-time using tee
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            echo "📺 [${agent_id}] Live output:"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
            claude --dangerously-skip-permissions --output-format json -p "$full_prompt" 2>&1 | tee "$temp_stdout" || exit_code=$?
            # Copy stdout to temp_stderr for completion signal check
            cp "$temp_stdout" "$temp_stderr"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        else
            # Normal mode: capture output silently
            claude --dangerously-skip-permissions --output-format json -p "$full_prompt" >"$temp_stdout" 2>"$temp_stderr" || exit_code=$?
        fi

        if [[ $exit_code -eq 0 ]]; then
            echo "✅ [${agent_id}] Iteration ${iteration} complete"

            # Try to parse cost from JSON output
            local cost
            cost=$(cat "$temp_stdout" | jq -r 'if type == "array" then .[-1] else . end | .cost_usd // .total_cost // 0' 2>/dev/null || echo "0")
            if [[ "$cost" != "0" && "$cost" != "null" ]]; then
                echo "   💰 Cost: \$${cost}"
            fi

            # Show last few lines of stderr (Claude's conversation output) - only in non-verbose mode
            if [[ "$VERBOSE" != "true" && -s "$temp_stderr" ]]; then
                echo "   📝 Output (last 5 lines):"
                tail -5 "$temp_stderr" | sed 's/^/      /'
            fi
        else
            echo "❌ [${agent_id}] Iteration ${iteration} failed (exit code: ${exit_code})"
            if [[ -s "$temp_stderr" ]]; then
                tail -10 "$temp_stderr"
            fi
        fi

        # Check for completion signal in output
        if grep -q "$completion_signal" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
            echo "🎉 [${agent_id}] Agent signaled completion"
            rm -f "$temp_stdout" "$temp_stderr"
            break
        fi

        # Cleanup temp files
        rm -f "$temp_stdout" "$temp_stderr"

        # Brief pause between iterations
        sleep 2
    done

    update_agent_state "$agent_id" "completed"
    echo "✅ [${agent_id}] Agent finished after ${iteration} iterations"
}

# Run agents in sequence (pipeline)
# Usage: run_agent_pipeline <prompt> <agents>
run_agent_pipeline() {
    local prompt="$1"
    local agents="$2"
    local max_runs="${3:-5}"
    local branch_name="continuous-claude/swarm-${SWARM_SESSION_ID}"
    local notes_file="SHARED_TASK_NOTES.md"

    # Create a working branch for the swarm
    if git rev-parse --git-dir > /dev/null 2>&1; then
        local main_branch
        main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

        echo "🌿 Creating swarm branch: ${branch_name}"
        git checkout -b "$branch_name" 2>/dev/null || git checkout "$branch_name" 2>/dev/null || true
    fi

    for agent_id in $agents; do
        echo ""
        echo "═══════════════════════════════════════════════════════════════"
        echo "  Starting: ${agent_id}"
        echo "═══════════════════════════════════════════════════════════════"

        # Build agent-specific prompt based on role
        local agent_prompt
        agent_prompt=$(build_agent_prompt "$agent_id" "$prompt")

        execute_agent "$agent_id" "$agent_prompt" "$max_runs"

        # Show dashboard after each agent
        print_coordination_dashboard
    done

    # Create PR if we have changes
    if git rev-parse --git-dir > /dev/null 2>&1; then
        create_swarm_pr "$branch_name" "$prompt"
    fi
}

# Build role-specific prompt for each agent
# Usage: build_agent_prompt <agent_id> <base_prompt>
build_agent_prompt() {
    local agent_id="$1"
    local base_prompt="$2"
    local notes_file="SHARED_TASK_NOTES.md"

    case "$agent_id" in
        planner)
            echo "## PLANNING TASK

Analyze the following request and create a detailed implementation plan:

${base_prompt}

Your deliverables:
1. Break down the task into specific implementation steps
2. Identify files that need to be created or modified
3. Define acceptance criteria for each step
4. Document any dependencies or considerations

Write your plan to ${notes_file} so the Developer agent can follow it."
            ;;
        developer)
            echo "## DEVELOPMENT TASK

Implement the feature/fix based on the plan in ${notes_file}:

Original request: ${base_prompt}

Your responsibilities:
1. Read the plan from ${notes_file}
2. Implement the code changes step by step
3. Follow the acceptance criteria defined in the plan
4. Update ${notes_file} with what you completed and any issues found
5. Commit your changes with descriptive messages

Do NOT write tests - the Tester agent will handle that."
            ;;
        tester)
            echo "## TESTING TASK

Write tests for the implementation documented in ${notes_file}:

Original request: ${base_prompt}

Your responsibilities:
1. Read ${notes_file} to understand what was implemented
2. Write comprehensive tests (unit tests, integration tests as needed)
3. Run the tests and ensure they pass
4. Update ${notes_file} with test coverage information
5. If tests fail, document the failures for the Developer

Do NOT fix implementation bugs - document them in ${notes_file} for the Developer."
            ;;
        reviewer)
            echo "## CODE REVIEW TASK

Review the code changes and prepare for PR:

Original request: ${base_prompt}

Your responsibilities:
1. Read ${notes_file} to understand the implementation and tests
2. Review the code for quality, security, and best practices
3. Check that all acceptance criteria are met
4. Update ${notes_file} with your review summary
5. If changes are needed, document them clearly

If everything looks good, add 'APPROVED_FOR_MERGE' to ${notes_file}."
            ;;
        *)
            # Default: use base prompt
            echo "${base_prompt}"
            ;;
    esac
}

# Create a PR for the swarm work
# Usage: create_swarm_pr <branch_name> <prompt>
create_swarm_pr() {
    local branch_name="$1"
    local prompt="$2"
    local notes_file="SHARED_TASK_NOTES.md"

    # Check if there are any commits to push
    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@' || echo "main")

    local commit_count
    commit_count=$(git rev-list --count "${main_branch}..HEAD" 2>/dev/null || echo "0")

    if [[ "$commit_count" -eq 0 ]]; then
        echo "⚠️  No commits to create PR"
        return 0
    fi

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Creating Pull Request"
    echo "═══════════════════════════════════════════════════════════════"

    # Push the branch
    echo "📤 Pushing branch: ${branch_name}"
    git push -u origin "$branch_name" 2>/dev/null || {
        echo "⚠️  Failed to push branch"
        return 1
    }

    # Get PR body from notes file if exists
    local pr_body="## Summary

This PR was created by Continuous Claude Swarm.

**Original Task:** ${prompt}

"
    if [[ -f "$notes_file" ]]; then
        pr_body+="## Implementation Notes

\`\`\`
$(cat "$notes_file")
\`\`\`
"
    fi

    pr_body+="
---
🤖 Generated with [Continuous Claude](https://github.com/primadonna-gpters/continuous-claude)"

    # Create PR using gh CLI
    if command -v gh &>/dev/null; then
        local pr_url
        pr_url=$(gh pr create \
            --title "🤖 ${prompt:0:60}" \
            --body "$pr_body" \
            --base "$main_branch" \
            --head "$branch_name" 2>&1) || {
            echo "⚠️  Failed to create PR: $pr_url"
            return 1
        }
        echo "✅ PR created: ${pr_url}"

        # Auto-merge if enabled
        if [[ "$AUTO_MERGE" == "true" ]]; then
            echo "🔀 Auto-merge enabled, merging PR..."
            gh pr merge "$pr_url" --squash --delete-branch || {
                echo "⚠️  Auto-merge failed"
            }
        fi
    else
        echo "⚠️  gh CLI not found. Please create PR manually:"
        echo "   gh pr create --base $main_branch --head $branch_name"
    fi
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
    export SWARM_SESSION_ID="${SWARM_SESSION_ID:-$(date +%Y%m%d-%H%M%S)}"

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
