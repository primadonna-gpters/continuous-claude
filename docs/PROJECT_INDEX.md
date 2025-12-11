# Continuous Claude - Project Index

> **Version**: v0.14.0 (Core) + v2.1 (Multi-Agent System)
> **Last Updated**: 2025-12-10
> **Total Lines**: ~8,300+ (Shell scripts)

---

## 📋 Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Core Components](#core-components)
- [Multi-Agent System](#multi-agent-system)
- [Dashboard](#dashboard)
- [Personas](#personas)
- [API Reference](#api-reference)
- [Configuration](#configuration)
- [Quick Start](#quick-start)

---

## Overview

Continuous Claude is an automated workflow tool that orchestrates Claude Code in a continuous loop, autonomously creating PRs, waiting for checks, and merging - so multi-step projects complete while you sleep.

### Key Features

| Feature | Description |
|---------|-------------|
| **Continuous Loop** | Runs Claude Code iteratively until task completion |
| **PR Lifecycle** | Automated branch creation, PR, CI checks, and merge |
| **Context Continuity** | Shared notes file maintains state across iterations |
| **Parallel Execution** | Git worktrees enable multiple simultaneous instances |
| **Multi-Agent Swarm** | Persona-based agents collaborate on complex tasks |
| **Learning System** | Captures failures and injects insights into prompts |
| **Real-time Dashboard** | WebSocket-powered monitoring and visualization |

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Continuous Claude                                │
│                                                                         │
│  ┌───────────────────┐     ┌───────────────────────────────────────┐  │
│  │ continuous_claude │     │         Multi-Agent Swarm              │  │
│  │       .sh         │     │                                        │  │
│  │                   │     │  ┌─────────┐ ┌─────────┐ ┌─────────┐ │  │
│  │  • Single agent   │     │  │Developer│ │ Tester  │ │Reviewer │ │  │
│  │  • PR lifecycle   │     │  │  Agent  │ │  Agent  │ │  Agent  │ │  │
│  │  • Cost tracking  │     │  └────┬────┘ └────┬────┘ └────┬────┘ │  │
│  │  • Worktree mgmt  │     │       └───────────┼───────────┘      │  │
│  └───────────────────┘     │                   ▼                   │  │
│                             │           ┌───────────┐              │  │
│                             │           │Orchestrator│              │  │
│                             │           └───────────┘              │  │
│                             └───────────────────────────────────────┘  │
│                                                                         │
│  ┌───────────────────────────────────────────────────────────────────┐ │
│  │                        Shared Infrastructure                       │ │
│  │                                                                    │ │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌─────────┐│ │
│  │  │ Messaging│ │ Personas │ │Worktrees │ │ Learning │ │Dashboard││ │
│  │  │   Queue  │ │  System  │ │  Manager │ │  Memory  │ │ Server  ││ │
│  │  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └─────────┘│ │
│  └───────────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Core Components

### Main Script

| File | Description |
|------|-------------|
| `continuous_claude.sh` | Main CLI entry point for single-agent continuous loop |
| `install.sh` | One-line installation script |

### Library Modules (`lib/`)

| Module | Purpose | Key Functions |
|--------|---------|---------------|
| `messaging.sh` | Inter-agent communication | `create_message`, `deliver_messages`, `get_unread_messages` |
| `personas.sh` | Agent role management | `load_persona`, `generate_persona_prompt`, `validate_persona` |
| `worktrees.sh` | Git worktree isolation | `create_agent_worktree`, `cleanup_session_worktrees` |
| `orchestrator.sh` | Swarm lifecycle control | `init_swarm`, `shutdown_swarm`, `process_agent_signal` |
| `conflicts.sh` | Conflict detection/resolution | `detect_conflicts`, `resolve_conflict`, `acquire_lock` |
| `coordination.sh` | High-level coordination API | `run_swarm`, `run_agent_pipeline`, `execute_agent`, `log_activity` |
| `learning.sh` | Failure capture & learning | `capture_failure`, `create_insight`, `inject_insights_into_prompt` |
| `review.sh` | Automated code review | `review_pr`, `run_static_analysis`, `submit_pr_review` |
| `dashboard.sh` | Dashboard server management | `start_dashboard`, `stop_dashboard`, `log_to_dashboard` |

---

## Multi-Agent System

### Coordination Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Pipeline** | Sequential execution (dev → test → review) | Standard feature development |
| **Parallel** | Concurrent independent work | Multi-component development |
| **Adaptive** | Dynamic mode switching based on progress | Complex projects with varying needs |

### Agent Communication Flow

```
┌─────────────────────────────────────────────────────────────┐
│                   Pipeline Workflow                          │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│   📋 Planner → 🧑‍💻 Developer → 🧪 Tester → 👁️ Reviewer     │
│                    ↑              │           │             │
│                    │    BUGS_FOUND│           │             │
│                    └──────────────┘           │             │
│                    ↑                          │             │
│                    │  REVIEW_CHANGES_REQUESTED│             │
│                    └──────────────────────────┘             │
│                                               │             │
│                                    REVIEW_APPROVED          │
│                                               ↓             │
│                                          PR Ready           │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

### Agent Signals

| Signal | Agent | Description |
|--------|-------|-------------|
| `AGENT_TASK_COMPLETE` | All | Agent finished current task |
| `PROJECT_COMPLETE` | All | Entire project finished |
| `BUGS_FOUND` | Tester | Tests failed, needs developer fix |
| `REVIEW_APPROVED` | Reviewer | Code approved, PR ready for merge |
| `REVIEW_CHANGES_REQUESTED` | Reviewer | Changes needed, back to developer |

### Message Types

| Category | Types |
|----------|-------|
| **Task** | `task.assigned`, `task.started`, `task.completed`, `task.failed` |
| **Feature** | `feature.implemented`, `feature.tested`, `feature.approved` |
| **Test** | `test.passed`, `test.failed` |
| **Review** | `review.comment`, `review.approved`, `review.changes_requested` |

---

## Dashboard

### Backend (FastAPI)

**Location**: `dashboard/backend/`

| File | Purpose |
|------|---------|
| `main.py` | FastAPI application with WebSocket support |
| `db/database.py` | SQLite async connection management |
| `db/models.py` | SQLAlchemy ORM models |
| `models/schemas.py` | Pydantic validation schemas |
| `routes/agents.py` | Agent CRUD endpoints |
| `routes/tasks.py` | Task queue management |
| `routes/websocket.py` | Real-time event broadcasting |

### Frontend (Svelte 5)

**Location**: `dashboard/frontend/`

| File | Purpose |
|------|---------|
| `src/lib/stores/dashboard.ts` | Reactive state management |
| `src/lib/components/AgentCard.svelte` | Agent status display |
| `src/lib/components/LogStream.svelte` | Real-time log viewer |
| `src/routes/+page.svelte` | Main dashboard page |

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/sessions` | GET/POST | List/create sessions |
| `/api/sessions/{id}` | GET/PATCH | Session details/update |
| `/api/agents` | GET/POST | List/create agents |
| `/api/agents/{id}` | GET/PATCH/DELETE | Agent CRUD |
| `/api/tasks` | GET/POST | List/create tasks |
| `/api/tasks/queue` | GET | Task queue by status |
| `/api/dashboard/{session_id}` | GET | Complete dashboard state |
| `/ws/{session_id}` | WebSocket | Real-time updates |

### WebSocket Events

| Event | Description |
|-------|-------------|
| `agent.status_changed` | Agent status update |
| `task.progress_updated` | Task progress change |
| `message.sent` | Inter-agent message |
| `log.entry` | New log entry |
| `cost.updated` | Cost change |
| `session.complete` | Session finished |

---

## Personas

### Available Personas (`personas/`)

| Persona | Emoji | Role | Next Phase |
|---------|-------|------|------------|
| **Planner** | 📋 | Requirements analysis, task breakdown | Developer |
| **Developer** | 🧑‍💻 | Feature implementation, bug fixes | Tester |
| **Tester** | 🧪 | Test writing, execution, coverage | Reviewer (pass) / Developer (fail) |
| **Reviewer** | 👁️ | Code review, PR approval | Merge (approved) / Developer (changes) |
| **Documenter** | 📚 | Documentation, README updates | - |
| **Security** | 🔒 | Security scanning, vulnerability fixes | - |

### Persona Schema

```yaml
persona:
  id: string           # Unique identifier
  name: string         # Display name
  emoji: string        # Visual identifier
  role: string         # Role description

  responsibilities:    # List of duties
    - string

  constraints:         # Behavioral limits
    - string

  communication:
    listens_to:        # Message types received
      - string
    publishes:         # Message types sent
      - string

  tools:
    allowed:           # Permitted operations
      - string
    denied:            # Forbidden operations
      - string
```

---

## API Reference

### CLI Commands

```bash
# Single-agent continuous loop
continuous-claude --prompt "..." --max-runs N

# With cost/duration limits
continuous-claude --prompt "..." --max-cost 10.00
continuous-claude --prompt "..." --max-duration 2h

# Parallel execution
continuous-claude --prompt "..." --worktree agent1
continuous-claude --prompt "..." --worktree agent2

# Multi-agent swarm
source lib/coordination.sh
run_swarm "Build auth system" pipeline "developer tester reviewer"
```

### Library Functions

#### Messaging (`lib/messaging.sh`)

```bash
# Create and send message
create_message "from" "to" "type" "subject" '{"body":"json"}'

# Get unread messages for agent
get_unread_messages "agent_id"

# Send typed messages
send_feature_complete "developer" "auth-module" '["file1","file2"]'
send_test_results "tester" "passed" '{"coverage":85}'
send_review_feedback "reviewer" "approved" '["comment1"]' 123
```

#### Learning (`lib/learning.sh`)

```bash
# Initialize database
init_learning_db

# Capture failure
capture_failure "session" "agent" 3 "test_failure" "Error msg" '["files"]'

# Create insight
create_insight "jwt_check" "test_failure" "Token expiration" "Add exp check"

# Generate prompt injection
generate_insights_prompt "test_failure"
```

#### Review (`lib/review.sh`)

```bash
# Review PR (preview)
review_pr 123

# Review and submit
review_pr 123 owner/repo --submit

# Run static analysis
run_static_analysis ./src
```

#### Dashboard (`lib/dashboard.sh`)

```bash
# Server management
start_dashboard 8000
stop_dashboard
get_dashboard_status

# Logging
log_to_dashboard "session" "info" "Message" "agent_id"
```

---

## Configuration

### Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SWARM_DIR` | `.continuous-claude` | Swarm state directory |
| `PERSONAS_DIR` | `personas` | Persona definitions |
| `LEARNING_DIR` | `.continuous-claude/learning` | Learning database |
| `DASHBOARD_PORT` | `8000` | Dashboard server port |
| `COORDINATION_MODE` | `pipeline` | Default coordination mode |
| `AUTO_MERGE` | `false` | Auto-merge on approval |
| `MAX_INSIGHTS_IN_PROMPT` | `5` | Insights to inject |

### State Files

```
.continuous-claude/
├── state/
│   ├── session.json      # Current session info
│   ├── agents.json       # Agent states
│   ├── tasks.json        # Task queue
│   └── activity.log      # Real-time activity log (dashboard)
├── messages/
│   ├── inbox/{agent}/    # Per-agent inbox
│   └── outbox/pending/   # Outgoing messages
├── learning/
│   ├── insights.db       # SQLite learning DB
│   └── failures.json     # Failure log
└── locks/                # File locks
```

---

## Quick Start

### Installation

```bash
curl -fsSL https://raw.githubusercontent.com/primadonna-gpters/continuous-claude/main/install.sh | bash
```

### Prerequisites

- [Claude Code CLI](https://code.claude.com) - `claude auth`
- [GitHub CLI](https://cli.github.com) - `gh auth login`
- `jq` - JSON processing
- Python 3.11+ (for dashboard)

### Basic Usage

```bash
# Single agent continuous loop
continuous-claude -p "Add unit tests" -m 10

# Multi-agent swarm
cd your-project
source /path/to/continuous-claude/lib/coordination.sh
run_swarm "Implement auth feature" pipeline "developer tester reviewer"

# Start dashboard
./lib/dashboard.sh start 8000
# Open http://localhost:8000
```

---

## Directory Structure

```
continuous-claude/
├── continuous_claude.sh       # Main CLI script
├── install.sh                 # Installation script
├── lib/
│   ├── messaging.sh          # Message queue system
│   ├── personas.sh           # Persona management
│   ├── worktrees.sh          # Worktree management
│   ├── orchestrator.sh       # Swarm orchestration
│   ├── conflicts.sh          # Conflict resolution
│   ├── coordination.sh       # Coordination engine
│   ├── learning.sh           # Learning system
│   ├── review.sh             # Code review
│   └── dashboard.sh          # Dashboard management
├── personas/
│   ├── developer.yaml
│   ├── tester.yaml
│   ├── reviewer.yaml
│   ├── documenter.yaml
│   └── security.yaml
├── dashboard/
│   ├── backend/              # FastAPI server
│   │   ├── main.py
│   │   ├── db/
│   │   ├── models/
│   │   └── routes/
│   └── frontend/             # Svelte 5 UI
│       └── src/
├── tests/                    # Test suite
├── docs/                     # Documentation
└── .continuous-claude/       # Runtime state (gitignored)
```

---

## Contributing

See [CHANGELOG.md](../CHANGELOG.md) for version history.

## License

[MIT](../LICENSE) © [Anand Chowdhary](https://anandchowdhary.com)
