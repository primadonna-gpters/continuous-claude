# Continuous Claude - Quick Reference Cheatsheet

## CLI Commands

```bash
# Single agent - basic
continuous-claude -p "Your task" -m 10

# With cost limit
continuous-claude -p "Task" --max-cost 10.00

# With time limit
continuous-claude -p "Task" --max-duration 2h

# Parallel with worktrees
continuous-claude -p "Task A" -m 5 --worktree agent1
continuous-claude -p "Task B" -m 5 --worktree agent2
```

## Multi-Agent Swarm

```bash
# Source library
source lib/coordination.sh

# Pipeline mode (sequential)
run_swarm "Build feature" pipeline "developer tester reviewer"

# Parallel mode (concurrent)
run_swarm "Build components" parallel "developer developer tester"

# Adaptive mode (auto-switch)
run_swarm "Complex project" adaptive "developer tester reviewer"
```

## Dashboard

```bash
./lib/dashboard.sh start [port]  # Start server
./lib/dashboard.sh stop          # Stop server
./lib/dashboard.sh status        # Check status
# Open http://localhost:8000
```

## Learning System

```bash
source lib/learning.sh

init_learning_db              # Initialize
install_prebuilt_insights     # Add common insights

# Capture failure
capture_failure "session" "agent" 5 "test_failure" "Error message"

# Inject insights into prompt
enhanced=$(inject_insights_into_prompt "$prompt" "test_failure")
```

## Code Review

```bash
source lib/review.sh

review_pr 123                          # Preview review
review_pr 123 owner/repo --submit      # Submit to GitHub
run_static_analysis ./src              # Static analysis only
```

## Messaging

```bash
source lib/messaging.sh

# Send messages
create_message "from" "to" "type" "subject" '{"body":"json"}'
send_feature_complete "developer" "auth" '["file1.ts"]'
send_test_results "tester" "passed" "All tests pass"
send_review_feedback "reviewer" "approved" '[]' 123

# Read messages
get_unread_messages "agent_id"
get_unread_count "agent_id"
```

## Orchestrator

```bash
source lib/orchestrator.sh

# Initialize swarm
session_id=$(init_swarm "dev tester reviewer" "Task prompt")

# Manage agents
register_agent "agent_id" "persona_id"
start_agent "agent_id"
stop_agent "agent_id"

# Tasks
add_task "type" "agent_id" "description" 1 '{"payload":"json"}'
update_task_status "task_id" "completed"
get_pending_tasks "agent_id"

# Status
print_swarm_status
get_swarm_status_json
```

## Personas

```bash
source lib/personas.sh

list_personas                          # List all
load_persona "developer"               # Load one
get_persona_prompt "developer"         # Get system prompt
generate_persona_prompt "dev" "task"   # Full prompt
```

## Worktrees

```bash
source lib/worktrees.sh

create_agent_worktree "agent_id"       # Create
cleanup_agent_worktree "agent_id"      # Remove
list_agent_worktrees                   # List all
sync_worktree "agent_id"               # Sync with main
```

## Conflicts

```bash
source lib/conflicts.sh

acquire_lock "file.ts" "agent_id"      # Lock file
release_lock "file.ts" "agent_id"      # Unlock
check_lock "file.ts"                   # Check status
detect_conflicts                       # Find conflicts
cleanup_stale_locks                    # Remove old locks
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SWARM_DIR` | `.continuous-claude` | State directory |
| `COORDINATION_MODE` | `pipeline` | Default mode |
| `AUTO_MERGE` | `false` | Auto-merge PRs |
| `DASHBOARD_PORT` | `8000` | Dashboard port |
| `MAX_INSIGHTS_IN_PROMPT` | `5` | Insights limit |

## Personas

| ID | Emoji | Role |
|----|-------|------|
| `developer` | 🧑‍💻 | Feature implementation |
| `tester` | 🧪 | Test writing |
| `reviewer` | 👁️ | Code review |
| `documenter` | 📚 | Documentation |
| `security` | 🔒 | Security audit |

## Message Types

| Type | Description |
|------|-------------|
| `task.assigned` | Task assignment |
| `feature.implemented` | Feature ready |
| `test.passed` | Tests passing |
| `test.failed` | Tests failing |
| `review.approved` | Review approved |
| `review.changes_requested` | Changes needed |

## Failure Types

| Type | Description |
|------|-------------|
| `test_failure` | Test assertion failed |
| `build_failure` | Build/compile error |
| `lint_error` | Linting issues |
| `type_error` | Type check errors |
| `review_rejection` | PR rejected |

## Review Decisions

| Decision | When |
|----------|------|
| `APPROVE` | No blocking issues |
| `REQUEST_CHANGES` | Blockers found |
| `COMMENT` | Suggestions only |

## Severity Levels

| Level | Icon | Action |
|-------|------|--------|
| `blocker` | 🔴 | Must fix |
| `major` | 🟠 | Should fix |
| `minor` | 🟢 | Nice to have |
| `suggestion` | 💡 | Consider |

---

*Quick Reference v2.0*
