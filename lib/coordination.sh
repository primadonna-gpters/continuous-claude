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

# Completion signals
AGENT_TASK_COMPLETE="AGENT_TASK_COMPLETE"
PROJECT_COMPLETE="CONTINUOUS_CLAUDE_PROJECT_COMPLETE"

# Run a single agent iteration with Claude Code
# Usage: execute_agent <agent_id> <prompt> [max_runs]
# Returns: 0 on success, 1 on failure, 2 if bugs found (for tester)
execute_agent() {
    local agent_id="$1"
    local prompt="$2"
    local max_runs="${3:-5}"
    local notes_file="SHARED_TASK_NOTES.md"

    echo "🤖 [${agent_id}] Starting agent execution..."

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
            claude --dangerously-skip-permissions --output-format json -p "$full_prompt" 2>&1 | tee "$temp_stdout" || exit_code=$?
            cp "$temp_stdout" "$temp_stderr"
            echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        else
            claude --dangerously-skip-permissions --output-format json -p "$full_prompt" >"$temp_stdout" 2>"$temp_stderr" || exit_code=$?
        fi

        if [[ $exit_code -eq 0 ]]; then
            echo "✅ [${agent_id}] Iteration ${iteration} complete"

            # Parse cost from JSON output
            local cost
            cost=$(cat "$temp_stdout" | jq -r 'if type == "array" then .[-1] else . end | .cost_usd // .total_cost // 0' 2>/dev/null || echo "0")
            if [[ "$cost" != "0" && "$cost" != "null" ]]; then
                echo "   💰 Cost: \$${cost}"
            fi

            # Show output summary in non-verbose mode
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

        # Check for task completion signal (agent finished its work)
        if grep -q "$AGENT_TASK_COMPLETE" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
            echo "✅ [${agent_id}] Agent completed its task"
            rm -f "$temp_stdout" "$temp_stderr"
            break
        fi

        # Check for project completion signal
        if grep -q "$PROJECT_COMPLETE" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
            echo "🎉 [${agent_id}] Project complete signal detected"
            rm -f "$temp_stdout" "$temp_stderr"
            break
        fi

        # Check if tester found bugs (special handling)
        if [[ "$agent_id" == "tester" ]]; then
            if grep -q "BUGS_FOUND" "$temp_stdout" "$temp_stderr" 2>/dev/null; then
                echo "🐛 [${agent_id}] Bugs found - will need developer fix"
                agent_result=2
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
    full_prompt+="

## CRITICAL INSTRUCTIONS
- DO NOT ask questions. Proceed with reasonable defaults.
- DO NOT wait for confirmation. Just do the work.
- When your task is complete, include '${AGENT_TASK_COMPLETE}' in your response.
- Update ${notes_file} with your progress and any important notes for the next agent."

    echo "$full_prompt"
}

# Run agents in sequence (pipeline)
# Workflow: planner → developer → tester → (loop if bugs) → PR → reviewer
# Usage: run_agent_pipeline <prompt> <agents> [max_runs]
run_agent_pipeline() {
    local prompt="$1"
    local agents="$2"
    local max_runs="${3:-5}"
    local notes_file="SHARED_TASK_NOTES.md"
    local max_bug_fix_cycles=3

    # Create a working branch for the swarm
    local branch_name
    branch_name=$(create_swarm_branch)
    if [[ -z "$branch_name" ]]; then
        echo "⚠️  Not in a git repo, continuing without branch"
    fi

    # Phase 1: Planning
    if [[ "$agents" == *"planner"* ]]; then
        run_agent_phase "planner" "$prompt" "$max_runs" "Phase 1: Planning"
    fi

    # Phase 2: Development & Testing Loop
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
            run_agent_phase "developer" "$prompt" "$max_runs" "Phase 2: Development"
        fi

        # Tester phase
        if [[ "$agents" == *"tester"* ]]; then
            run_agent_phase "tester" "$prompt" "$max_runs" "Phase 3: Testing"
            local tester_result=$?

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
        echo "⚠️  Max bug fix cycles reached, proceeding anyway"
    fi

    # Phase 4: Create PR (before reviewer)
    local pr_url=""
    if [[ -n "$branch_name" ]]; then
        pr_url=$(create_swarm_pr "$branch_name" "$prompt")
    fi

    # Phase 5: Review (reviews the actual PR)
    if [[ "$agents" == *"reviewer"* ]]; then
        local reviewer_prompt
        reviewer_prompt=$(build_agent_prompt "reviewer" "$prompt" "$pr_url")
        run_agent_phase "reviewer" "$reviewer_prompt" "$max_runs" "Phase 4: Code Review"
    fi

    echo ""
    echo "🎉 Pipeline completed!"
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

    local agent_prompt
    agent_prompt=$(build_agent_prompt "$agent_id" "$prompt")

    execute_agent "$agent_id" "$agent_prompt" "$max_runs"
    local result=$?

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
            if [[ -n "$pr_url" ]]; then
                pr_section="
## Pull Request to Review
${pr_url}

Use 'gh pr view ${pr_url}' to see the PR details.
Use 'gh pr diff ${pr_url}' to see the code changes.
"
            fi
            cat << EOF
# 👁️ REVIEWER AGENT TASK

## Your Mission
Review the code changes and provide feedback.
${pr_section}
## Original Request
${base_prompt}

## Review Checklist
1. **Code Quality**: Clean, readable, follows best practices
2. **Security**: No vulnerabilities, proper input validation
3. **Tests**: Adequate coverage, tests are meaningful
4. **Documentation**: Code is well-commented where needed
5. **Acceptance Criteria**: All requirements from plan are met

## Instructions
1. Read ${notes_file} for context
2. Review the code changes
3. Check test results
4. Provide constructive feedback

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

If approved, include 'APPROVED_FOR_MERGE' and 'AGENT_TASK_COMPLETE'.
If changes needed, document them clearly.
EOF
            ;;
        *)
            echo "${base_prompt}"
            ;;
    esac
}

# Create a PR for the swarm work
# Usage: create_swarm_pr <branch_name> <prompt>
# Returns: PR URL (echoed to stdout)
create_swarm_pr() {
    local branch_name="$1"
    local prompt="$2"
    local notes_file="SHARED_TASK_NOTES.md"

    # Check if there are any commits to push
    local main_branch
    main_branch=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
    main_branch="${main_branch:-main}"

    local commit_count
    commit_count=$(git rev-list --count "${main_branch}..HEAD" 2>/dev/null || echo "0")

    if [[ "$commit_count" -eq 0 ]]; then
        echo "⚠️  No commits to create PR" >&2
        return 0
    fi

    echo "" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2
    echo "  Creating Pull Request" >&2
    echo "═══════════════════════════════════════════════════════════════" >&2

    # Push the branch
    echo "📤 Pushing branch: ${branch_name}" >&2
    if ! git push -u origin "$branch_name" 2>/dev/null; then
        echo "⚠️  Failed to push branch" >&2
        return 1
    fi

    # Build PR body
    local pr_body="## Summary

This PR was created by Continuous Claude Swarm.

**Original Task:** ${prompt}

**Session:** ${SWARM_SESSION_ID}
"
    if [[ -f "$notes_file" ]]; then
        pr_body+="
## Implementation Notes

<details>
<summary>Click to expand</summary>

\`\`\`markdown
$(cat "$notes_file")
\`\`\`

</details>
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
            --head "$branch_name" 2>/dev/null)

        if [[ -n "$pr_url" ]]; then
            echo "✅ PR created: ${pr_url}" >&2
            # Return PR URL to stdout for capture
            echo "$pr_url"
            return 0
        else
            echo "⚠️  Failed to create PR" >&2
            return 1
        fi
    else
        echo "⚠️  gh CLI not found. Please create PR manually:" >&2
        echo "   gh pr create --base $main_branch --head $branch_name" >&2
        return 1
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
    # Use timestamp + PID + random for unique session ID
    export SWARM_SESSION_ID="${SWARM_SESSION_ID:-$(date +%Y%m%d-%H%M%S)-$$-$(printf '%04x' $RANDOM)}"

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
