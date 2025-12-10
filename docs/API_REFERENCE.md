# Continuous Claude - API Reference

> **Version**: v0.14.0 (Core) + v2.0 (Multi-Agent System)
> **Last Updated**: 2025-12-10

---

## Table of Contents

- [Messaging API](#messaging-api)
- [Coordination API](#coordination-api)
- [Orchestrator API](#orchestrator-api)
- [Learning API](#learning-api)
- [Review API](#review-api)
- [Dashboard API](#dashboard-api)
- [Personas API](#personas-api)
- [Worktrees API](#worktrees-api)
- [Conflicts API](#conflicts-api)

---

## Messaging API

**File**: `lib/messaging.sh`

Inter-agent communication system using file-based message queues.

### Configuration

```bash
SWARM_DIR="${SWARM_DIR:-.continuous-claude}"
MESSAGES_DIR="$SWARM_DIR/messages"
INBOX_DIR="$MESSAGES_DIR/inbox"
OUTBOX_DIR="$MESSAGES_DIR/outbox"
```

### Functions

#### `init_messaging`

Initialize messaging directories for a specific agent.

```bash
init_messaging <agent_id>
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `agent_id` | string | Unique identifier for the agent |

**Example:**
```bash
init_messaging "developer"
```

---

#### `init_all_messaging`

Initialize messaging for multiple agents at once.

```bash
init_all_messaging <agent1> <agent2> ...
```

**Example:**
```bash
init_all_messaging "developer" "tester" "reviewer"
```

---

#### `create_message`

Create and queue a message for delivery.

```bash
create_message <from> <to> <type> <subject> <body>
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `from` | string | Sender agent ID |
| `to` | string | Recipient agent ID |
| `type` | string | Message type (e.g., `notification`, `task`, `feedback`) |
| `subject` | string | Message subject line |
| `body` | JSON | Message body as JSON string |

**Returns:** Message ID

**Example:**
```bash
msg_id=$(create_message "developer" "tester" "notification" \
  "Feature ready" '{"feature":"auth","files":["login.ts"]}')
```

---

#### `create_priority_message`

Create a high-priority message (placed at front of queue).

```bash
create_priority_message <from> <to> <type> <subject> <body>
```

Same parameters as `create_message`.

---

#### `deliver_messages`

Deliver all pending messages from outbox to recipients' inboxes.

```bash
deliver_messages
```

**Returns:** Number of messages delivered

---

#### `deliver_message`

Deliver a specific message by ID.

```bash
deliver_message <message_id>
```

---

#### `get_unread_messages`

Get all unread messages for an agent.

```bash
get_unread_messages <agent_id>
```

**Returns:** JSON array of unread messages

**Example:**
```bash
messages=$(get_unread_messages "developer")
echo "$messages" | jq '.[0].subject'
```

---

#### `get_all_messages`

Get all messages (read and unread) for an agent.

```bash
get_all_messages <agent_id>
```

---

#### `read_message`

Mark a message as read.

```bash
read_message <agent_id> <message_id>
```

---

#### `get_unread_count`

Get count of unread messages for an agent.

```bash
get_unread_count <agent_id>
```

**Returns:** Integer count

---

#### `get_messages_by_type`

Filter messages by type.

```bash
get_messages_by_type <agent_id> <type>
```

**Example:**
```bash
get_messages_by_type "developer" "feedback"
```

---

#### `get_messages_from`

Get messages from a specific sender.

```bash
get_messages_from <agent_id> <sender_id>
```

---

#### `get_recent_messages`

Get most recent N messages.

```bash
get_recent_messages <agent_id> <count>
```

---

#### `delete_message`

Delete a specific message.

```bash
delete_message <agent_id> <message_id>
```

---

#### `cleanup_read_messages`

Remove all read messages from an agent's inbox.

```bash
cleanup_read_messages <agent_id>
```

**Returns:** Number of messages deleted

---

### Typed Message Functions

#### `send_task_assignment`

Send a task assignment to an agent.

```bash
send_task_assignment <from> <to> <description> <details_json>
```

---

#### `send_feature_complete`

Notify that a feature is ready for testing.

```bash
send_feature_complete <from> <feature_name> <files_json> [notes]
```

**Example:**
```bash
send_feature_complete "developer" "auth-module" '["login.ts","auth.ts"]' "JWT implemented"
```

---

#### `send_test_results`

Send test results to relevant agents.

```bash
send_test_results <from> <status> <summary> [details_json]
```

| Parameter | Type | Values |
|-----------|------|--------|
| `status` | string | `passed`, `failed` |
| `summary` | string | Human-readable summary |
| `details_json` | JSON | Coverage, test counts, etc. |

---

#### `send_review_feedback`

Send code review feedback.

```bash
send_review_feedback <from> <decision> <comments_json> [pr_number]
```

| Parameter | Type | Values |
|-----------|------|--------|
| `decision` | string | `approved`, `changes_requested`, `comment` |

---

#### `wait_for_message`

Block until a message of specified type arrives.

```bash
wait_for_message <agent_id> <message_type> [timeout_seconds]
```

**Returns:** The message JSON, or exits with code 1 on timeout

**Example:**
```bash
if msg=$(wait_for_message "tester" "feature.implemented" 300); then
    echo "Received feature notification"
fi
```

---

### CLI Interface

```bash
source lib/messaging.sh

# Available CLI commands
messaging_cli init <agent_id>
messaging_cli send <from> <to> <type> <subject> <body>
messaging_cli inbox <agent_id>
messaging_cli unread <agent_id>
messaging_cli read <agent_id> <message_id>
messaging_cli deliver
messaging_cli count <agent_id>
```

---

## Coordination API

**File**: `lib/coordination.sh`

High-level coordination engine for multi-agent workflows.

### Configuration

```bash
COORDINATION_MODE="${COORDINATION_MODE:-pipeline}"  # pipeline | parallel | adaptive
AUTO_MERGE="${AUTO_MERGE:-false}"
WORKFLOW_PIPELINE="developer tester reviewer"
WORKFLOW_PARALLEL="developer developer tester"
```

### Functions

#### `run_swarm`

Main entry point for multi-agent orchestration.

```bash
run_swarm <prompt> <mode> <agents>
```

| Parameter | Type | Values |
|-----------|------|--------|
| `prompt` | string | Task description |
| `mode` | string | `pipeline`, `parallel`, `adaptive` |
| `agents` | string | Space-separated agent list |

**Example:**
```bash
run_swarm "Build authentication system" "pipeline" "developer tester reviewer"
```

---

#### `run_pipeline`

Execute agents in sequence (dev → test → review).

```bash
run_pipeline <prompt>
```

---

#### `run_parallel`

Execute agents concurrently.

```bash
run_parallel <prompt>
```

---

#### `run_adaptive`

Dynamically switch between pipeline and parallel based on progress.

```bash
run_adaptive <prompt>
```

---

#### `get_next_in_pipeline`

Get the next agent in the pipeline workflow.

```bash
get_next_in_pipeline <current_agent>
```

**Returns:** Next agent ID or empty string if last

---

#### `get_previous_in_pipeline`

Get the previous agent in the pipeline workflow.

```bash
get_previous_in_pipeline <current_agent>
```

---

#### `notify_next_agent`

Notify the next agent in workflow that work is ready.

```bash
notify_next_agent <current_agent> <signal_type> <payload_json>
```

---

### Event Handlers

#### `on_developer_complete`

Called when developer finishes a feature.

```bash
on_developer_complete <feature> <files_json> [notes]
```

---

#### `on_tests_complete`

Called when tester finishes testing.

```bash
on_tests_complete <status> <summary> [details_json]
```

---

#### `on_review_complete`

Called when reviewer finishes review.

```bash
on_review_complete <decision> <comments_json> [pr_number]
```

---

#### `get_coordination_status`

Get current coordination system status.

```bash
get_coordination_status
```

**Returns:** JSON with swarm status, conflicts, worktrees

---

#### `print_coordination_dashboard`

Print a formatted dashboard to terminal.

```bash
print_coordination_dashboard
```

---

### CLI Interface

```bash
source lib/coordination.sh

coordination_cli swarm <prompt> <mode> <agents>
coordination_cli pipeline <prompt>
coordination_cli parallel <prompt>
coordination_cli status
coordination_cli dashboard
```

---

## Orchestrator API

**File**: `lib/orchestrator.sh`

Swarm lifecycle management and state tracking.

### Configuration

```bash
SWARM_DIR="${SWARM_DIR:-.continuous-claude}"
STATE_DIR="$SWARM_DIR/state"
```

### State Management Functions

#### `init_state`

Initialize state directories and files.

```bash
init_state
```

---

#### `update_agent_state`

Update an agent's state.

```bash
update_agent_state <agent_id> <status> [extra_json]
```

| Parameter | Type | Values |
|-----------|------|--------|
| `status` | string | `idle`, `running`, `waiting`, `error`, `stopped` |
| `extra_json` | JSON | Additional state data |

---

#### `get_agent_state`

Get current state of an agent.

```bash
get_agent_state <agent_id>
```

**Returns:** JSON object with agent state

---

#### `get_all_agents_state`

Get state of all registered agents.

```bash
get_all_agents_state
```

**Returns:** JSON object with all agents

---

#### `update_session_state`

Update the overall session state.

```bash
update_session_state <status> [extra_json]
```

---

#### `get_session_state`

Get current session state.

```bash
get_session_state
```

---

### Task Management Functions

#### `add_task`

Add a new task to the queue.

```bash
add_task <task_type> <agent_id> <description> [priority] [payload_json]
```

| Parameter | Type | Default |
|-----------|------|---------|
| `priority` | integer | 5 (1=highest, 10=lowest) |

**Returns:** Task ID

**Example:**
```bash
task_id=$(add_task "implement" "developer" "Add login endpoint" 1)
```

---

#### `update_task_status`

Update a task's status.

```bash
update_task_status <task_id> <status> [result_json]
```

| Parameter | Type | Values |
|-----------|------|--------|
| `status` | string | `pending`, `in_progress`, `completed`, `failed` |

---

#### `get_pending_tasks`

Get pending tasks for an agent.

```bash
get_pending_tasks [agent_id]
```

---

#### `get_next_task`

Get the highest priority pending task for an agent.

```bash
get_next_task <agent_id>
```

**Returns:** Task JSON or empty

---

#### `get_task_queue_summary`

Get summary counts of tasks by status.

```bash
get_task_queue_summary
```

**Returns:** JSON with `pending`, `in_progress`, `completed`, `failed` counts

---

### Agent Lifecycle Functions

#### `register_agent`

Register a new agent in the swarm.

```bash
register_agent <agent_id> <persona_id>
```

---

#### `start_agent`

Mark an agent as running.

```bash
start_agent <agent_id>
```

---

#### `stop_agent`

Mark an agent as stopped.

```bash
stop_agent <agent_id>
```

---

#### `increment_iteration`

Increment an agent's iteration counter.

```bash
increment_iteration <agent_id>
```

**Returns:** New iteration number

---

#### `unregister_agent`

Remove an agent from the swarm.

```bash
unregister_agent <agent_id>
```

---

### Swarm Lifecycle Functions

#### `init_swarm`

Initialize a new swarm session.

```bash
init_swarm <agents_list> <prompt>
```

| Parameter | Type | Description |
|-----------|------|-------------|
| `agents_list` | string | Space-separated agent IDs |
| `prompt` | string | Main task description |

**Returns:** Session ID

**Example:**
```bash
session_id=$(init_swarm "developer tester reviewer" "Build auth system")
```

---

#### `shutdown_swarm`

Gracefully shut down all agents.

```bash
shutdown_swarm
```

---

#### `distribute_initial_tasks`

Distribute the initial prompt as tasks to agents.

```bash
distribute_initial_tasks <prompt>
```

---

#### `process_agent_signal`

Process a signal from an agent (feature complete, tests passed, etc.).

```bash
process_agent_signal <agent_id> <signal_type> [payload_json]
```

| Signal Type | Description |
|-------------|-------------|
| `feature_complete` | Developer finished implementing |
| `tests_passed` | All tests passing |
| `tests_failed` | Tests failed |
| `review_approved` | Code review approved |
| `review_changes_requested` | Changes requested |

---

#### `process_pending_messages`

Process all pending messages for agents.

```bash
process_pending_messages
```

---

#### `print_swarm_status`

Print formatted swarm status.

```bash
print_swarm_status
```

---

#### `get_swarm_status_json`

Get complete swarm status as JSON.

```bash
get_swarm_status_json
```

---

### CLI Interface

```bash
source lib/orchestrator.sh

orchestrator_cli init <agents> <prompt>
orchestrator_cli shutdown
orchestrator_cli status
orchestrator_cli agent-state <agent_id>
orchestrator_cli task-add <type> <agent_id> <description>
orchestrator_cli task-status <task_id> <status>
orchestrator_cli signal <agent_id> <signal_type> [payload]
```

---

## Learning API

**File**: `lib/learning.sh`

Failure learning and insight injection system.

### Configuration

```bash
LEARNING_DIR="${SWARM_DIR:-.continuous-claude}/learning"
INSIGHTS_DB="$LEARNING_DIR/insights.json"
FAILURES_LOG="$LEARNING_DIR/failures.json"
MAX_INSIGHTS_IN_PROMPT="${MAX_INSIGHTS_IN_PROMPT:-5}"
INSIGHT_MIN_CONFIDENCE="${INSIGHT_MIN_CONFIDENCE:-0.3}"
```

### Functions

#### `init_learning_db`

Initialize the learning database.

```bash
init_learning_db
```

---

#### `capture_failure`

Record a failure for analysis.

```bash
capture_failure <session_id> <agent_id> <iteration> <failure_type> <error_message> [affected_files_json] [context_json]
```

| Parameter | Type | Values |
|-----------|------|--------|
| `failure_type` | string | `test_failure`, `build_failure`, `lint_error`, `type_error`, `review_rejection` |

**Example:**
```bash
capture_failure "session-123" "developer" 5 "test_failure" \
  "Expected 401, got 200" '["auth/login.ts"]'
```

---

#### `parse_ci_failure`

Parse CI logs to extract failure information.

```bash
parse_ci_failure <log_file_or_stdin>
```

**Returns:** JSON with `failure_type`, `error_message`, `affected_files`

**Example:**
```bash
# From file
result=$(parse_ci_failure /path/to/ci.log)

# From stdin
cat ci.log | parse_ci_failure
gh pr checks 123 | parse_ci_failure
```

---

#### `parse_review_rejection`

Parse PR reviews to extract rejection reasons.

```bash
parse_review_rejection <pr_number> [repo]
```

**Returns:** JSON with rejection comments

---

#### `create_insight`

Create a new learning insight.

```bash
create_insight <pattern> <failure_type> <description> <solution> [root_cause] [code_hint] [files_pattern]
```

**Example:**
```bash
create_insight "jwt_expiration" "test_failure" \
  "Missing token expiration check" \
  "Add exp claim validation in jwt.verify()" \
  "Token validation missing expiration check" \
  'if (decoded.exp < Date.now()/1000) throw new Error("Expired")'
```

---

#### `get_relevant_insights`

Get insights relevant to a failure type or file pattern.

```bash
get_relevant_insights [failure_type] [file_pattern] [limit]
```

**Returns:** JSON array of matching insights

---

#### `record_insight_application`

Record that an insight was applied.

```bash
record_insight_application <pattern> <session_id> <agent_id> <iteration> <was_successful> [notes]
```

---

#### `generate_insights_prompt`

Generate prompt section with relevant insights.

```bash
generate_insights_prompt [failure_type] [file_pattern]
```

**Returns:** Markdown-formatted insights section

---

#### `inject_insights_into_prompt`

Inject insights into an existing prompt.

```bash
inject_insights_into_prompt <original_prompt> [failure_type] [file_pattern]
```

**Returns:** Enhanced prompt with insights

**Example:**
```bash
enhanced=$(inject_insights_into_prompt "$prompt" "test_failure" "auth/*")
claude "$enhanced"
```

---

#### `analyze_failures`

Get analysis of recent failures.

```bash
analyze_failures [session_id] [limit]
```

---

#### `get_failure_stats`

Get failure statistics.

```bash
get_failure_stats [session_id]
```

**Returns:** JSON with failure counts by type

---

#### `get_insight_effectiveness`

Get effectiveness metrics for insights.

```bash
get_insight_effectiveness
```

**Returns:** JSON with success rates per insight

---

#### `install_prebuilt_insights`

Install common pre-built insights.

```bash
install_prebuilt_insights
```

Installs insights for:
- JWT expiration handling
- Database connection pools
- Async/await patterns
- TypeScript strict mode
- ESLint configuration
- Python import errors

---

### CLI Interface

```bash
source lib/learning.sh

learning_cli init
learning_cli capture <session> <agent> <iteration> <type> <message> [files]
learning_cli parse-ci [log_file]
learning_cli insight <pattern> <type> <description> <solution>
learning_cli get-insights [type] [file_pattern]
learning_cli inject <prompt> [type] [file_pattern]
learning_cli stats [session]
learning_cli install-prebuilt
```

---

## Review API

**File**: `lib/review.sh`

Automated code review system with static analysis integration.

### Configuration

```bash
REVIEW_CONFIG_FILE=".continuous-claude/review.yaml"
REVIEW_CACHE_DIR=".continuous-claude/cache/reviews"

# Severity levels
SEVERITY_BLOCKER="blocker"
SEVERITY_MAJOR="major"
SEVERITY_MINOR="minor"
SEVERITY_SUGGESTION="suggestion"
```

### Functions

#### `get_default_review_criteria`

Get default review criteria configuration.

```bash
get_default_review_criteria
```

**Returns:** JSON with review criteria categories

---

#### `load_review_config`

Load review configuration from file.

```bash
load_review_config
```

---

### Static Analysis Functions

#### `run_eslint`

Run ESLint on JavaScript/TypeScript files.

```bash
run_eslint <files_json>
```

**Returns:** JSON array of issues

---

#### `run_ruff`

Run Ruff linter on Python files.

```bash
run_ruff <files_json>
```

**Returns:** JSON array of issues

---

#### `run_typecheck`

Run TypeScript type checking.

```bash
run_typecheck <files_json>
```

**Returns:** JSON array of type errors

---

#### `run_static_analysis`

Run all applicable static analysis tools.

```bash
run_static_analysis <directory>
```

**Returns:** JSON with results from all tools

**Example:**
```bash
results=$(run_static_analysis ./src)
echo "$results" | jq '.eslint.issues | length'
```

---

### PR Review Functions

#### `get_pr_diff`

Get the diff for a pull request.

```bash
get_pr_diff <pr_number> [repo]
```

**Returns:** Unified diff output

---

#### `get_pr_files`

Get list of files changed in a PR.

```bash
get_pr_files <pr_number> [repo]
```

**Returns:** JSON array of file paths

---

#### `get_pr_details`

Get PR metadata.

```bash
get_pr_details <pr_number> [repo]
```

**Returns:** JSON with title, body, author, branch, etc.

---

#### `create_review_finding`

Create a structured review finding.

```bash
create_review_finding <severity> <category> <file> <line> <message> [suggestion]
```

**Returns:** JSON finding object

---

#### `aggregate_findings`

Aggregate findings by severity and category.

```bash
aggregate_findings <findings_json>
```

**Returns:** JSON with categorized findings

---

#### `determine_decision`

Determine review decision based on findings.

```bash
determine_decision <findings_json>
```

**Returns:** `APPROVE`, `REQUEST_CHANGES`, or `COMMENT`

---

#### `generate_review_markdown`

Generate formatted review report.

```bash
generate_review_markdown <pr_number> <findings_json> <decision>
```

**Returns:** Markdown review body

---

#### `submit_pr_review`

Submit review to GitHub.

```bash
submit_pr_review <pr_number> <decision> <body> [repo]
```

---

#### `add_pr_comment`

Add inline comment to PR file.

```bash
add_pr_comment <pr_number> <file> <line> <body> [repo]
```

---

#### `review_pr`

Complete PR review workflow.

```bash
review_pr <pr_number> [repo] [--submit]
```

**Example:**
```bash
# Preview review
review_pr 123

# Review and submit to GitHub
review_pr 123 owner/repo --submit
```

---

### CLI Interface

```bash
source lib/review.sh

review_cli review <pr_number> [repo] [--submit]
review_cli analyze <directory>
review_cli criteria
```

---

## Dashboard API

**File**: `lib/dashboard.sh`

Dashboard server management.

### Functions

#### `start_dashboard`

Start the dashboard server.

```bash
start_dashboard [port]
```

| Parameter | Default | Description |
|-----------|---------|-------------|
| `port` | 8000 | HTTP port |

---

#### `stop_dashboard`

Stop the running dashboard server.

```bash
stop_dashboard
```

---

#### `restart_dashboard`

Restart the dashboard server.

```bash
restart_dashboard [port]
```

---

#### `get_dashboard_status`

Check if dashboard is running.

```bash
get_dashboard_status
```

**Returns:** JSON with `running`, `pid`, `port`

---

#### `get_dashboard_url`

Get the dashboard URL.

```bash
get_dashboard_url
```

**Returns:** URL string (e.g., `http://localhost:8000`)

---

#### `log_to_dashboard`

Send log entry to dashboard.

```bash
log_to_dashboard <session_id> <level> <message> [agent_id]
```

| Parameter | Values |
|-----------|--------|
| `level` | `info`, `warning`, `error`, `debug` |

---

### CLI Interface

```bash
./lib/dashboard.sh start [port]
./lib/dashboard.sh stop
./lib/dashboard.sh restart [port]
./lib/dashboard.sh status
./lib/dashboard.sh url
./lib/dashboard.sh log <session> <level> <message> [agent]
```

---

## Personas API

**File**: `lib/personas.sh`

Agent persona management system.

### Functions

#### `load_persona`

Load a persona definition.

```bash
load_persona <persona_id>
```

**Returns:** JSON persona object

---

#### `validate_persona`

Validate a persona file.

```bash
validate_persona <persona_file>
```

**Returns:** `true` if valid, `false` otherwise

---

#### `get_persona_prompt`

Get the system prompt for a persona.

```bash
get_persona_prompt <persona_id>
```

**Returns:** Formatted prompt string

---

#### `generate_persona_prompt`

Generate complete prompt including persona context.

```bash
generate_persona_prompt <persona_id> <task_prompt>
```

---

#### `list_personas`

List all available personas.

```bash
list_personas
```

**Returns:** JSON array of persona summaries

---

#### `get_persona_emoji`

Get the emoji for a persona.

```bash
get_persona_emoji <persona_id>
```

---

#### `get_persona_role`

Get the role description for a persona.

```bash
get_persona_role <persona_id>
```

---

### CLI Interface

```bash
source lib/personas.sh

personas_cli list
personas_cli load <persona_id>
personas_cli validate <file>
personas_cli prompt <persona_id>
personas_cli emoji <persona_id>
```

---

## Worktrees API

**File**: `lib/worktrees.sh`

Git worktree management for parallel execution.

### Functions

#### `create_agent_worktree`

Create an isolated worktree for an agent.

```bash
create_agent_worktree <agent_id> [base_dir]
```

**Returns:** Worktree path

---

#### `get_worktree_path`

Get the path for an agent's worktree.

```bash
get_worktree_path <agent_id> [base_dir]
```

---

#### `cleanup_agent_worktree`

Remove an agent's worktree.

```bash
cleanup_agent_worktree <agent_id> [base_dir]
```

---

#### `cleanup_session_worktrees`

Remove all worktrees for a session.

```bash
cleanup_session_worktrees <session_id>
```

---

#### `list_agent_worktrees`

List all active agent worktrees.

```bash
list_agent_worktrees
```

**Returns:** JSON array of worktree info

---

#### `sync_worktree`

Sync a worktree with main branch.

```bash
sync_worktree <agent_id>
```

---

### CLI Interface

```bash
source lib/worktrees.sh

worktrees_cli create <agent_id>
worktrees_cli cleanup <agent_id>
worktrees_cli list
worktrees_cli sync <agent_id>
```

---

## Conflicts API

**File**: `lib/conflicts.sh`

File locking and conflict resolution.

### Functions

#### `acquire_lock`

Acquire a lock on a file.

```bash
acquire_lock <file_path> <agent_id> [timeout]
```

**Returns:** `true` if lock acquired, `false` otherwise

---

#### `release_lock`

Release a lock on a file.

```bash
release_lock <file_path> <agent_id>
```

---

#### `check_lock`

Check if a file is locked.

```bash
check_lock <file_path>
```

**Returns:** JSON with `locked`, `owner`, `acquired_at`

---

#### `detect_conflicts`

Detect potential conflicts between agent changes.

```bash
detect_conflicts
```

**Returns:** JSON array of conflicts

---

#### `resolve_conflict`

Attempt to resolve a conflict.

```bash
resolve_conflict <conflict_id> <strategy>
```

| Strategy | Description |
|----------|-------------|
| `sequential` | One agent waits |
| `merge` | Attempt auto-merge |
| `priority` | Higher priority wins |

---

#### `get_active_locks`

Get all active file locks.

```bash
get_active_locks
```

---

#### `cleanup_stale_locks`

Remove locks older than timeout.

```bash
cleanup_stale_locks [timeout_seconds]
```

---

### CLI Interface

```bash
source lib/conflicts.sh

conflicts_cli lock <file> <agent_id>
conflicts_cli unlock <file> <agent_id>
conflicts_cli check <file>
conflicts_cli detect
conflicts_cli resolve <conflict_id> <strategy>
conflicts_cli list-locks
conflicts_cli cleanup
```

---

## Dashboard REST API

**Backend**: `dashboard/backend/main.py`

### Endpoints

#### Sessions

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/sessions` | List all sessions |
| POST | `/api/sessions` | Create new session |
| GET | `/api/sessions/{id}` | Get session details |
| PATCH | `/api/sessions/{id}` | Update session |

#### Agents

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/agents` | List all agents |
| POST | `/api/agents` | Register new agent |
| GET | `/api/agents/{id}` | Get agent details |
| PATCH | `/api/agents/{id}` | Update agent status |
| DELETE | `/api/agents/{id}` | Unregister agent |

#### Tasks

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/tasks` | List all tasks |
| POST | `/api/tasks` | Create new task |
| GET | `/api/tasks/{id}` | Get task details |
| PATCH | `/api/tasks/{id}` | Update task status |
| GET | `/api/tasks/queue` | Get tasks by status |

#### Dashboard

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/api/dashboard/{session_id}` | Get complete dashboard state |

### WebSocket Events

Connect to `/ws/{session_id}` for real-time updates.

#### Incoming Events (Server → Client)

| Event | Payload |
|-------|---------|
| `agent.status_changed` | `{ agent_id, status, iteration }` |
| `task.progress_updated` | `{ task_id, status, progress }` |
| `message.sent` | `{ from, to, type, subject }` |
| `log.entry` | `{ level, message, agent_id, timestamp }` |
| `cost.updated` | `{ total_cost, agent_costs }` |
| `session.complete` | `{ status, total_cost, duration }` |

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SWARM_DIR` | `.continuous-claude` | Base directory for swarm state |
| `PERSONAS_DIR` | `personas` | Persona definitions directory |
| `LEARNING_DIR` | `.continuous-claude/learning` | Learning database directory |
| `DASHBOARD_PORT` | `8000` | Dashboard server port |
| `COORDINATION_MODE` | `pipeline` | Default coordination mode |
| `AUTO_MERGE` | `false` | Auto-merge on approval |
| `MAX_INSIGHTS_IN_PROMPT` | `5` | Max insights to inject |
| `INSIGHT_MIN_CONFIDENCE` | `0.3` | Minimum insight confidence |

---

## Error Codes

| Code | Meaning |
|------|---------|
| `0` | Success |
| `1` | General error |
| `2` | Invalid arguments |
| `3` | File not found |
| `4` | Permission denied |
| `5` | Lock acquisition failed |
| `6` | Timeout |
| `7` | Conflict detected |

---

*Generated: 2025-12-10*
