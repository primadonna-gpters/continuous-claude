# Continuous Claude - User Guide

> A practical guide to running automated AI development workflows

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Single-Agent Mode](#single-agent-mode)
3. [Multi-Agent Swarm](#multi-agent-swarm)
4. [Dashboard](#dashboard)
5. [Learning System](#learning-system)
6. [Code Review](#code-review)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Getting Started

### Installation

```bash
# One-line install
curl -fsSL https://raw.githubusercontent.com/primadonna-gpters/continuous-claude/main/install.sh | bash
```

### Prerequisites

| Tool | Purpose | Installation |
|------|---------|--------------|
| Claude Code CLI | AI agent | `claude auth` |
| GitHub CLI | PR management | `gh auth login` |
| jq | JSON processing | `brew install jq` |
| Python 3.11+ | Dashboard | Required for dashboard |

### Verify Installation

```bash
# Check continuous-claude is installed
continuous-claude --help

# Verify dependencies
claude --version
gh --version
jq --version
```

---

## Single-Agent Mode

The simplest way to use Continuous Claude is single-agent mode, where one AI agent works on your task iteratively.

### Basic Usage

```bash
# Run with iteration limit
continuous-claude --prompt "Add unit tests to auth module" --max-runs 10

# Run with cost budget
continuous-claude --prompt "Improve code coverage" --max-cost 15.00

# Run with time limit
continuous-claude --prompt "Refactor database layer" --max-duration 2h
```

### How It Works

1. **Iteration Start**: Creates a new branch
2. **AI Work**: Claude Code executes your prompt
3. **Commit**: Changes are committed to the branch
4. **PR Creation**: A pull request is opened
5. **CI Wait**: Waits for all checks to pass
6. **Merge**: Auto-merges on success
7. **Repeat**: Pulls latest and starts next iteration

### Shared Notes File

The `SHARED_TASK_NOTES.md` file maintains context between iterations:

```markdown
# Task Notes

## Progress
- [x] Added login tests (iteration 1)
- [x] Added registration tests (iteration 2)
- [ ] Add password reset tests

## Next Steps
- Test edge cases for expired tokens
- Add integration tests

## Known Issues
- Mock database needs cleanup in afterEach
```

### Parallel Execution with Worktrees

Run multiple instances simultaneously using git worktrees:

```bash
# Terminal 1: Work on tests
continuous-claude -p "Add unit tests" -m 10 --worktree tests

# Terminal 2: Work on docs (simultaneously)
continuous-claude -p "Add documentation" -m 5 --worktree docs
```

Each worktree is isolated, preventing conflicts:

```
your-project/
../continuous-claude-worktrees/
  ├── tests/     # Worktree for test agent
  └── docs/      # Worktree for docs agent
```

### Key Flags

| Flag | Description | Example |
|------|-------------|---------|
| `-p, --prompt` | Task description | `-p "Add tests"` |
| `-m, --max-runs` | Iteration limit | `-m 10` |
| `--max-cost` | Budget in USD | `--max-cost 5.00` |
| `--max-duration` | Time limit | `--max-duration 1h` |
| `--worktree` | Isolated worktree | `--worktree dev` |
| `--merge-strategy` | squash/merge/rebase | `--merge-strategy squash` |
| `--notes-file` | Context file | `--notes-file CONTEXT.md` |
| `--disable-commits` | Test mode | `--disable-commits` |

---

## Multi-Agent Swarm

The swarm mode enables multiple specialized agents to collaborate on complex tasks.

### Quick Start

```bash
# Source the coordination library
source /path/to/continuous-claude/lib/coordination.sh

# Run a swarm with developer, tester, and reviewer
run_swarm "Build user authentication with JWT" pipeline "developer tester reviewer"
```

### Coordination Modes

#### Pipeline Mode
Agents work sequentially: Developer → Tester → Reviewer

```bash
run_swarm "Implement feature X" pipeline "developer tester reviewer"
```

Best for: Standard feature development with review

```
Developer                Tester                   Reviewer
    │                        │                        │
    │  1. Implement          │                        │
    │─────────────────>      │                        │
    │                        │  2. Write tests        │
    │                        │─────────────────>      │
    │                        │                        │  3. Review
    │  4. Fix feedback       │                        │
    │<─────────────────────────────────────────────── │
    │                        │                        │
    │  5. Re-implement       │                        │
    │─────────────────>      │  6. Re-test            │
    │                        │─────────────────>      │
    │                        │                        │  7. Approve
    │                        │                        │  ────> Merge
```

#### Parallel Mode
Multiple agents work concurrently on independent tasks

```bash
run_swarm "Build components" parallel "developer developer tester"
```

Best for: Multi-component development, large refactoring

#### Adaptive Mode
Dynamically switches between pipeline and parallel based on progress

```bash
run_swarm "Complex project" adaptive "developer tester reviewer documenter"
```

### Available Personas

| Persona | Emoji | Responsibilities |
|---------|-------|------------------|
| **developer** | 🧑‍💻 | Feature implementation, bug fixes |
| **tester** | 🧪 | Test writing, coverage analysis |
| **reviewer** | 👁️ | Code review, quality gates |
| **documenter** | 📚 | Documentation, README updates |
| **security** | 🔒 | Security scanning, vulnerability fixes |

### Agent Communication

Agents communicate through typed messages:

```bash
# Developer notifies tester
send_feature_complete "developer" "auth-module" '["login.ts","auth.ts"]' \
  "JWT authentication implemented"

# Tester notifies reviewer
send_test_results "tester" "passed" "All 45 tests passing, 92% coverage" \
  '{"coverage":92,"tests":45}'

# Reviewer sends feedback
send_review_feedback "reviewer" "changes_requested" \
  '["Add error handling for expired tokens"]' 123
```

### Swarm Status

Monitor swarm progress:

```bash
# Print formatted status
source lib/orchestrator.sh
print_swarm_status

# Output:
# ═══════════════════════════════════════════════════
#  Swarm Session: auth-impl-20251210-abc123
#  Status: running | Started: 2025-12-10 14:30:00
# ═══════════════════════════════════════════════════
#  Agents:
#    🧑‍💻 developer  │ running  │ iter: 3 │ 📬 0
#    🧪 tester      │ waiting  │ iter: 1 │ 📬 1
#    👁️ reviewer    │ idle     │ iter: 0 │ 📬 0
# ───────────────────────────────────────────────────
#  Tasks: ⏳ 2 │ 🔄 1 │ ✅ 3 │ ❌ 0
# ═══════════════════════════════════════════════════
```

---

## Dashboard

Real-time monitoring web interface for swarm sessions.

### Starting the Dashboard

```bash
# Start on default port (8000)
./lib/dashboard.sh start

# Start on custom port
./lib/dashboard.sh start 3000

# Check status
./lib/dashboard.sh status

# Stop dashboard
./lib/dashboard.sh stop
```

### Accessing the Dashboard

Open `http://localhost:8000` in your browser.

### Dashboard Features

#### Session View
- Session ID and status
- Total elapsed time
- Cumulative cost
- Overall success rate

#### Agent Cards
- Real-time status (idle/running/waiting/error)
- Current iteration number
- Individual cost tracking
- Unread message count

#### Task Queue
- Pending tasks with priority
- In-progress tasks with agent assignment
- Completed tasks history
- Failed tasks with error info

#### Live Logs
- Real-time log streaming
- Filterable by level (info/warning/error)
- Agent-specific logs

#### Metrics
- Total PRs created
- PRs merged vs failed
- Average iteration time
- Success rate trends

### Logging to Dashboard

```bash
source lib/dashboard.sh

# Log messages from your scripts
log_to_dashboard "session-123" "info" "Starting iteration 5" "developer"
log_to_dashboard "session-123" "warning" "Rate limit approaching"
log_to_dashboard "session-123" "error" "CI check failed"
```

---

## Learning System

Continuous Claude learns from failures to improve future attempts.

### How It Works

1. **Capture**: Failures are automatically recorded
2. **Analyze**: CI logs and PR rejections are parsed
3. **Create Insights**: Patterns and solutions are extracted
4. **Inject**: Relevant insights are added to future prompts

### Using the Learning System

```bash
source lib/learning.sh

# Initialize learning database
init_learning_db

# Install pre-built common insights
install_prebuilt_insights

# Capture a failure manually
capture_failure "session-123" "developer" 5 "test_failure" \
  "Expected 401, got 200" '["auth/login.ts"]'

# Parse CI logs automatically
cat ci-output.log | learning_cli parse-ci
```

### Pre-built Insights

The system comes with common insights:

| Pattern | Failure Type | Solution |
|---------|--------------|----------|
| `jwt_expiration` | test_failure | Add exp claim validation |
| `db_pool_exhaustion` | test_failure | Configure pool size, cleanup connections |
| `async_not_awaited` | test_failure | Ensure all promises are awaited |
| `ts_strict_null` | type_error | Enable strictNullChecks, add null guards |
| `eslint_config` | lint_error | Update .eslintrc configuration |
| `python_import` | build_failure | Fix circular imports, check __init__.py |

### Injecting Insights into Prompts

```bash
# Get enhanced prompt with relevant insights
original_prompt="Fix the failing tests in auth module"
enhanced=$(inject_insights_into_prompt "$original_prompt" "test_failure" "auth/*")

# The enhanced prompt now includes:
# ## LEARNED INSIGHTS FROM PREVIOUS FAILURES
#
# ### Insight #1: JWT Expiration Check
# - **Pattern**: jwt_expiration
# - **Root Cause**: Token validation missing expiration check
# - **Solution**: Add exp claim validation in jwt.verify()
# - **Code Hint**: if (decoded.exp < Date.now()/1000) throw new Error()
```

### Creating Custom Insights

```bash
# Create insight for a recurring issue
create_insight "redis_connection" "test_failure" \
  "Redis connection not closed in tests" \
  "Call redis.quit() in afterAll hook" \
  "Connection pool exhaustion during parallel tests" \
  'afterAll(async () => { await redis.quit(); })'
```

### Viewing Learning Stats

```bash
# Get failure statistics
learning_cli stats

# Get insight effectiveness
get_insight_effectiveness | jq '.[] | select(.success_rate > 0.8)'
```

---

## Code Review

Automated code review with static analysis integration.

### Basic Usage

```bash
source lib/review.sh

# Preview review (doesn't submit)
review_pr 123

# Review and submit to GitHub
review_pr 123 owner/repo --submit
```

### Review Process

1. **Static Analysis**: Runs ESLint, Ruff, TypeScript checks
2. **PR Analysis**: Examines diff and changed files
3. **Finding Generation**: Creates structured findings
4. **Decision**: Determines APPROVE/REQUEST_CHANGES/COMMENT
5. **Report**: Generates markdown review

### Review Criteria

The reviewer checks for:

| Category | Checks |
|----------|--------|
| **Code Quality** | Clean code, SOLID, DRY, naming |
| **Security** | Input validation, SQL injection, XSS |
| **Performance** | Algorithm efficiency, memory, queries |
| **Maintainability** | Documentation, tests, error handling |

### Severity Levels

| Level | Icon | Action |
|-------|------|--------|
| Blocker | 🔴 | Must fix before merge |
| Major | 🟠 | Should fix, may approve |
| Minor | 🟢 | Nice to have |
| Suggestion | 💡 | Consider for future |

### Review Output Example

```markdown
## Code Review Summary

**PR**: #123 - Implement JWT Authentication
**Reviewer**: 👁️ Code Review Agent
**Decision**: 🟡 REQUEST CHANGES

### Findings

#### 🔴 Blocker (1)
1. **[SECURITY]** Token expiration not validated
   - File: `src/auth/middleware.ts:45`
   - Suggestion: Check `decoded.exp < Date.now()/1000`

#### 🟠 Major (2)
1. **[QUALITY]** Duplicate code in handlers
2. **[SECURITY]** Password logged in debug mode

### Required Actions
- [ ] Fix token expiration validation
- [ ] Remove password from logs
```

### Running Static Analysis Only

```bash
# Analyze a directory
run_static_analysis ./src

# Run specific linter
run_eslint '["src/index.ts", "src/auth.ts"]'
run_ruff '["app/main.py", "app/auth.py"]'
run_typecheck '["src/**/*.ts"]'
```

---

## Best Practices

### Prompt Engineering

**Do:**
```bash
# Specific, actionable prompts
continuous-claude -p "Add unit tests for the UserService class in src/services/user.ts.
Focus on the createUser and deleteUser methods. Target 80% coverage."
```

**Don't:**
```bash
# Vague prompts
continuous-claude -p "Add some tests"
```

### Cost Management

```bash
# Set both limits for safety
continuous-claude -p "Refactor auth module" \
  --max-runs 20 \
  --max-cost 10.00 \
  --max-duration 2h
```

### Iteration Strategy

For large tasks, break them down:

```bash
# Iteration 1-5: Foundation
continuous-claude -p "Set up test infrastructure" -m 5

# Iteration 6-15: Core tests
continuous-claude -p "Add tests for core services" -m 10

# Iteration 16-20: Edge cases
continuous-claude -p "Add edge case tests" -m 5
```

### Swarm Composition

| Task | Recommended Agents |
|------|-------------------|
| Simple feature | developer, tester |
| Feature with review | developer, tester, reviewer |
| Documentation | developer, documenter |
| Security fix | developer, security, tester |
| Large refactor | developer, developer, tester, reviewer |

### Context File Management

Keep `SHARED_TASK_NOTES.md` focused:

```markdown
# Task: Add Authentication

## Current Status
Working on: JWT token validation

## Completed
- [x] User model
- [x] Login endpoint
- [x] Password hashing

## Blocked
- Waiting for: Redis setup for session storage

## Notes for Next Iteration
- Token refresh endpoint needed
- Consider rate limiting
```

---

## Troubleshooting

### Common Issues

#### "Claude not found"

```bash
# Ensure Claude Code CLI is installed and authenticated
claude auth
```

#### "GitHub CLI not authenticated"

```bash
gh auth login
gh auth status
```

#### "PR checks timeout"

The default timeout is 30 minutes. If your CI is slow:

```bash
# Increase timeout in the script or set environment variable
export PR_CHECK_TIMEOUT=3600  # 1 hour
```

#### "Worktree conflicts"

```bash
# List worktrees
continuous-claude --list-worktrees

# Clean up orphaned worktrees
git worktree prune
```

#### "Dashboard won't start"

```bash
# Check if port is in use
lsof -i :8000

# Check Python version
python3 --version  # Should be 3.11+

# Install dependencies
cd dashboard/backend
pip install -r requirements.txt
```

#### "Learning database errors"

```bash
# Reinitialize the database
rm -rf .continuous-claude/learning/
source lib/learning.sh
init_learning_db
install_prebuilt_insights
```

### Debug Mode

```bash
# Run with verbose output
export DEBUG=1
continuous-claude -p "Task" -m 1

# Test without commits
continuous-claude -p "Task" -m 1 --disable-commits
```

### Getting Help

```bash
# View help
continuous-claude --help

# Check version
continuous-claude --version

# View documentation
open https://github.com/primadonna-gpters/continuous-claude
```

---

## Example Workflows

### Adding Test Coverage

```bash
continuous-claude \
  --prompt "Increase test coverage to 80% for src/services/.
    Focus on uncovered branches and error paths.
    Use Jest with React Testing Library." \
  --max-runs 20 \
  --max-cost 15.00 \
  --notes-file TEST_COVERAGE_NOTES.md
```

### Multi-Agent Feature Development

```bash
source lib/coordination.sh

run_swarm "Implement OAuth2 authentication with Google and GitHub providers.
Include:
- OAuth flow handlers
- User linking to existing accounts
- Token refresh mechanism
- Integration tests" \
  pipeline \
  "developer tester reviewer"
```

### Documentation Sprint

```bash
source lib/coordination.sh

run_swarm "Update all documentation for v2.0 release:
- Update README with new features
- Add API documentation
- Create migration guide from v1.x" \
  parallel \
  "documenter documenter developer"
```

### Security Audit

```bash
source lib/coordination.sh

run_swarm "Perform security audit and fix vulnerabilities:
- Run npm audit and fix
- Check for SQL injection
- Validate all user inputs
- Add rate limiting" \
  pipeline \
  "security developer tester"
```

---

*Guide Version: 2.0 | Last Updated: 2025-12-10*
