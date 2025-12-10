<h1><img width="512" height="294" alt="Continuous Claude" src="https://github.com/user-attachments/assets/26878379-6cff-4803-a50d-c1e3f9455f55" /></h1>

<p align="center">
  <strong>Run Claude Code in a continuous loop with Multi-Agent Collaboration</strong><br>
  Automated PR workflow • Multi-Agent Swarm • Real-time Dashboard • Learning System
</p>

<p align="center">
  <img src="https://img.shields.io/badge/version-v2.0.0-blue" alt="Version">
  <img src="https://img.shields.io/badge/Claude_Code-CLI-purple" alt="Claude Code">
  <img src="https://img.shields.io/badge/Multi--Agent-Swarm-green" alt="Multi-Agent">
  <img src="https://img.shields.io/badge/license-MIT-lightgrey" alt="License">
</p>

---

<details>
  <summary>📖 <strong>Background Story</strong> - How Continuous Claude was born</summary>

This all started because I was contractually obligated to write unit tests for a codebase with hundreds of thousands of lines of code and go from 0% to 80%+ coverage in the next few weeks - seems like something Claude should do. So I built [Continuous Claude](https://github.com/AnandChowdhary/continuous-claude), a CLI tool to run Claude Code in a loop that maintains a persistent context across multiple iterations.

Current AI coding tools tend to halt after completing a task once they think the job is done and they don't really have an opportunity for self-criticism or further improvement. And this one-shot pattern then makes it difficult to tackle larger projects. So in contrast to running Claude Code "as is" (which provides help in isolated bursts), what you want is to run Claude code for a long period of time without exhausting the context window.

Turns out, it's as simple as just running Claude Code in a continuous loop - but drawing inspiration from CI/CD practices and persistent agents - you can take it a step further by running it on a schedule or through triggers and connecting it to your GitHub pull requests workflow. And by persisting relevant context and results from one iteration to the next, this process ensures that knowledge gained in earlier steps is not lost, which is currently not possible in stateless AI queries and something you have to slap on top by setting up markdown files to store progress and context engineer accordingly.

## While + git + persistence

The first version of this idea was a simple while loop:

```bash
while true; do
  claude --dangerously-skip-permissions "Increase test coverage [...] write notes for the next developer in TASKS.md, [etc.]"
  sleep 1
done
```

to which my friend [Namanyay](https://nmn.gl) of Giga AI said "genius and hilarious". I spent all of Saturday building the rest of the tooling. Now, the Bash script acts as the conductor, repeatedly invoking Claude Code with the appropriate prompts and handling the surrounding tooling. For each iteration, the script:

1. Creates a new branch and runs Claude Code to generate a commit
2. Pushes changes and creates a pull request using GitHub's CLI
3. Monitors CI checks and reviews via `gh pr checks`
4. Merges on success or discards on failure
5. Pulls the updated main branch, cleans up, and repeats

When an iteration fails, it closes the PR and discards the work. This is wasteful, but with knowledge of test failures, the next attempt can try something different. Because it piggybacks on GitHub's existing workflows, you get code review and preview environments without additional work - if your repo requires code owner approval or specific CI checks, it will respect those constraints.

## Context continuity

A shared markdown file serves as external memory where Claude records what it has done and what should be done next. Without specific prompting instructions, it would create verbose logs that harm more than help - the intent is to keep notes as a clean handoff package between runs. So the key instruction to the model is: "This is part of a continuous development loop... you don't need to complete the entire goal in one iteration, just make meaningful progress on one thing, then leave clear notes for the next iteration... think of it as a relay race where you're passing the baton."

Here's an actual production example: the previous iteration ended with "Note: tried adding tests to X but failed on edge case, need to handle null input in function Y" and the very next Claude invocation saw that and prioritized addressing it. A single small file reduces context drift, where it might forget earlier reasoning and go in circles.

What's fascinating is how the markdown file enables self-improvement. A simple "increase coverage" from the user becomes "run coverage, find files with low coverage, do one at a time" as the system teaches itself through iteration and keeps track of its own progress.

## Continuous AI

My friends at GitHub Next have been exploring this idea in their project [Continuous AI](https://githubnext.com/projects/continuous-ai/) and I shared Continuous Claude with them.

One compelling idea from the team was running specialized agents simultaneously - one for development, another for tests, a third for refactoring. While this could divide and conquer complex tasks more efficiently, it possibly introduces coordination challenges. I'm trying a similar approach for adding tests in different parts of a monorepository at the same time.

The [agentics project](https://github.com/githubnext/agentics) combines an explicit research phase with pre-build steps to ensure the software is restored before agentic work begins. "The fault-tolerance of Agent in a Loop is really important. If things go wrong it just hits the resource limits and tries again. Or the user just throws the generated PR away if it's not helpful. It's so much better than having a frustrated user trying to guide an agent that's gone down a wrong path," said GitHub Next Principal Researcher [Don Syme](https://github.com/dsyme).

It reminded me of a concept in economics/mathematics called "radiation of probabilities" (I know, pretty far afield, but bear with me) and here, each agent run is like a random particle - not analyzed individually, but the general direction emerges from the distribution. Each run can even be thought of as idempotent: if GitHub Actions kills the process after six hours, you only lose some dirty files that the next agent will pick up anyway. All you care about is that it's moving in the right direction in general, for example increasing test coverage, rather than what an individual agent does. This wasteful-but-effective approach becomes viable as token costs approach zero, similar to Cursor's multiple agents.

## Dependabot on steroids

Tools like Dependabot handle dependency updates, but Continuous Claude can also fix post-update breaking changes using release notes. You could run a GitHub Actions workflow every morning that checks for updates and continuously fixes issues until all tests pass.

Large refactoring tasks become manageable: breaking a monolith into modules, modernizing callbacks to async/await, or updating to new style guidelines. It could perform a series of 20 pull requests over a weekend, each doing part of the refactor with full CI validation. There's a whole class of tasks that are too mundane for humans but still require attention to avoid breaking the build.

The model mirrors human development practices. Claude Code handles the grunt work, but humans remain in the loop through familiar mechanisms like PR reviews. Download the CLI from GitHub to get started!

</details>

## 📋 Table of Contents

- [How it Works](#️-how-it-works)
- [Quick Start](#-quick-start)
- [Flags](#-flags)
- [Examples](#-examples)
- [Multi-Agent Swarm (v2.0)](#-multi-agent-swarm-v20)
- [Dashboard](#-dashboard)
- [Learning System](#-learning-system)
- [Automated Code Review](#️-automated-code-review)
- [Agent Management](#-agent-management)
- [Documentation](#-documentation)

---

## ⚙️ How it works

Using Claude Code to drive iterative development, this script fully automates the PR lifecycle from code changes through to merged commits.

### Single-Agent Mode

```
┌─────────────────────────────────────────────────────────────┐
│  📝 Your Prompt: "Add unit tests to auth module"           │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
         ┌─────────────────────────────────────┐
         │        🔁 Continuous Loop           │
         │  ┌─────────────────────────────┐   │
         │  │ 1. Create branch            │   │
         │  │ 2. Run Claude Code          │   │
         │  │ 3. Commit changes           │   │
         │  │ 4. Create PR                │   │
         │  │ 5. Wait for CI checks       │   │
         │  │ 6. Merge PR                 │   │
         │  │ 7. Pull latest & repeat     │   │
         │  └─────────────────────────────┘   │
         │                                     │
         │  📋 SHARED_TASK_NOTES.md maintains  │
         │     context between iterations      │
         └─────────────────────────────────────┘
```

### Multi-Agent Swarm (v2.0)

```
┌─────────────────────────────────────────────────────────────┐
│                    🎯 Orchestrator                          │
│         Coordinates agents • Resolves conflicts             │
└───────────────────────────┬─────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        ▼                   ▼                   ▼
  ┌───────────┐       ┌───────────┐       ┌───────────┐
  │ 🧑‍💻 Dev    │──────▶│ 🧪 Test   │──────▶│ 👁️ Review │
  │ Agent     │       │ Agent     │       │ Agent     │
  └───────────┘       └───────────┘       └───────────┘
        │                   │                   │
        └───────────────────┴───────────────────┘
                            │
                   ┌────────┴────────┐
                   │ 📊 Dashboard    │
                   │ 🧠 Learning DB  │
                   │ 💬 Message Queue│
                   └─────────────────┘
```

| Feature | Single-Agent | Multi-Agent Swarm |
|---------|--------------|-------------------|
| Agents | 1 | Multiple (dev, test, reviewer, etc.) |
| Coordination | Sequential loops | Pipeline / Parallel / Adaptive |
| Communication | Notes file | Message queue system |
| Learning | ❌ | ✅ Failure insights |
| Dashboard | ❌ | ✅ Real-time monitoring |
| Code Review | Manual | ✅ Automated |

## 🚀 Quick start

### Installation

Install with a single command:

```bash
curl -fsSL https://raw.githubusercontent.com/primadonna-gpters/continuous-claude/main/install.sh | bash
```

This will:

- Install `continuous-claude` to `~/.local/bin`
- Install Multi-Agent System modules to `~/.local/share/continuous-claude/lib/`
- Install persona definitions to `~/.local/share/continuous-claude/personas/`
- Check for required dependencies
- Guide you through adding it to your PATH if needed

> **Note**: You can override the default repository with environment variables:
> ```bash
> REPO_OWNER=your-fork REPO_BRANCH=dev curl -fsSL https://raw.githubusercontent.com/your-fork/continuous-claude/dev/install.sh | bash
> ```

### Manual installation

For v2.0 features, use the installer script above. For basic single-agent mode only:

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/primadonna-gpters/continuous-claude/main/continuous_claude.sh -o continuous-claude

# Make it executable
chmod +x continuous-claude

# Move to a directory in your PATH
sudo mv continuous-claude /usr/local/bin/
```

To uninstall `continuous-claude`:

```bash
# Remove executable
rm ~/.local/bin/continuous-claude
rm ~/.local/bin/.continuous-claude-core

# Remove Multi-Agent System modules and personas
rm -rf ~/.local/share/continuous-claude/

# Or if you installed to /usr/local/bin:
sudo rm /usr/local/bin/continuous-claude
```

### Prerequisites

Before using `continuous-claude`, you need:

1. **[Claude Code CLI](https://code.claude.com)** - Authenticate with `claude auth`
2. **[GitHub CLI](https://cli.github.com)** - Authenticate with `gh auth login`
3. **jq** - Install with `brew install jq` (macOS) or `apt-get install jq` (Linux)
4. **Python 3.11+** (optional) - Required for dashboard: `pip install fastapi uvicorn aiosqlite`

### Usage

```bash
# Run with your prompt, max runs, and GitHub repo (owner and repo auto-detected from git remote)
continuous-claude --prompt "add unit tests until all code is covered" --max-runs 5

# Or explicitly specify the owner and repo
continuous-claude --prompt "add unit tests until all code is covered" --max-runs 5 --owner your-username --repo your-repo

# Or run with a cost budget instead
continuous-claude --prompt "add unit tests until all code is covered" --max-cost 10.00

# Or run for a specific duration (time-boxed bursts)
continuous-claude --prompt "add unit tests until all code is covered" --max-duration 2h
```

## 🎯 Flags

- `-p, --prompt`: Task prompt for Claude Code (required)
- `-m, --max-runs`: Maximum number of iterations, use `0` for infinite (required unless --max-cost or --max-duration is provided)
- `--max-cost`: Maximum USD to spend (required unless --max-runs or --max-duration is provided)
- `--max-duration`: Maximum duration to run (e.g., `2h`, `30m`, `1h30m`) (required unless --max-runs or --max-cost is provided)
- `--owner`: GitHub repository owner (auto-detected from git remote if not provided)
- `--repo`: GitHub repository name (auto-detected from git remote if not provided)
- `--merge-strategy`: Merge strategy: `squash`, `merge`, or `rebase` (default: `squash`)
- `--git-branch-prefix`: Prefix for git branch names (default: `continuous-claude/`)
- `--notes-file`: Path to shared task notes file (default: `SHARED_TASK_NOTES.md`)
- `--disable-commits`: Disable automatic git commits, PR creation, and merging (useful for testing)
- `--worktree <name>`: Run in a git worktree for parallel execution (creates if needed)
- `--worktree-base-dir <path>`: Base directory for worktrees (default: `../continuous-claude-worktrees`)
- `--cleanup-worktree`: Remove worktree after completion
- `--list-worktrees`: List all active git worktrees and exit
- `--dry-run`: Simulate execution without making changes
- `--completion-signal <phrase>`: Phrase that agents output when entire project is complete (default: `CONTINUOUS_CLAUDE_PROJECT_COMPLETE`)
- `--completion-threshold <num>`: Number of consecutive completion signals required to stop early (default: `3`)

Any additional flags you provide that are not recognized by `continuous-claude` will be automatically forwarded to the underlying `claude` command. For example, you can pass `--allowedTools`, `--model`, or any other Claude Code CLI flags.

## 📝 Examples

```bash
# Run 5 iterations (owner and repo auto-detected from git remote)
continuous-claude -p "improve code quality" -m 5

# Run infinitely until stopped
continuous-claude -p "add unit tests until all code is covered" -m 0

# Run until $10 budget exhausted
continuous-claude -p "add documentation" --max-cost 10.00

# Run for 2 hours (time-boxed burst)
continuous-claude -p "add unit tests" --max-duration 2h

# Run for 30 minutes
continuous-claude -p "refactor module" --max-duration 30m

# Run for 1 hour and 30 minutes
continuous-claude -p "add features" --max-duration 1h30m

# Run max 10 iterations or $5, whichever comes first
continuous-claude -p "refactor code" -m 10 --max-cost 5.00

# Combine duration and cost limits (whichever comes first)
continuous-claude -p "improve tests" --max-duration 1h --max-cost 5.00

# Use merge commits instead of squash
continuous-claude -p "add features" -m 5 --merge-strategy merge

# Use rebase strategy
continuous-claude -p "update dependencies" -m 3 --merge-strategy rebase

# Use custom branch prefix
continuous-claude -p "refactor code" -m 3 --git-branch-prefix "feature/"

# Use custom notes file
continuous-claude -p "add features" -m 5 --notes-file "PROJECT_CONTEXT.md"

# Test without creating commits or PRs
continuous-claude -p "test changes" -m 2 --disable-commits

# Pass additional Claude Code CLI flags (e.g., restrict tools)
continuous-claude -p "add features" -m 3 --allowedTools "Write,Read"

# Use a different model
continuous-claude -p "refactor code" -m 5 --model claude-haiku-4-5

# Enable early stopping when agents signal project completion
continuous-claude -p "add unit tests to all files" -m 50 --completion-threshold 3

# Use custom completion signal
continuous-claude -p "fix all bugs" -m 20 --completion-signal "ALL_BUGS_FIXED" --completion-threshold 2

# Explicitly specify owner and repo (useful if git remote is not set up or not a GitHub repo)
continuous-claude -p "add features" -m 5 --owner myuser --repo myproject

# Check for and install updates
continuous-claude update
```

### Running in parallel

Use git worktrees to run multiple instances simultaneously without conflicts:

```bash
# Terminal 1 (owner and repo auto-detected)
continuous-claude -p "Add unit tests" -m 5 --worktree tests

# Terminal 2 (simultaneously)
continuous-claude -p "Add docs" -m 5 --worktree docs
```

Each instance creates its own worktree at `../continuous-claude-worktrees/<name>/`, pulls the latest changes, and runs independently. Worktrees persist for reuse.

```bash
# List worktrees
continuous-claude --list-worktrees

# Clean up after completion
continuous-claude -p "task" -m 1 --worktree temp --cleanup-worktree
```

## 📊 Example output

Here's what a successful run looks like:

```
🔄 (1/1) Starting iteration...
🌿 (1/1) Creating branch: continuous-claude/iteration-1/2025-11-15-be939873
🤖 (1/1) Running Claude Code...
📝 (1/1) Output: Perfect! I've successfully completed this iteration of the testing project. Here's what I accomplished: [...]
💰 (1/1) Cost: $0.042
✅ (1/1) Work completed
🌿 (1/1) Creating branch: continuous-claude/iteration-1/2025-11-15-be939873
💬 (1/1) Committing changes...
📦 (1/1) Changes committed on branch: continuous-claude/iteration-1/2025-11-15-be939873
📤 (1/1) Pushing branch...
🔨 (1/1) Creating pull request...
🔍 (1/1) PR #893 created, waiting 5 seconds for GitHub to set up...
🔍 (1/1) Checking PR status (iteration 1/180)...
   📊 Found 6 check(s)
   🟢 2    🟡 4    🔴 0
   👁️  Review status: None
⏳ Waiting for: checks to complete
✅ (1/1) All PR checks and reviews passed
🔀 (1/1) Merging PR #893...
📥 (1/1) Pulling latest from main...
🗑️ (1/1) Deleting local branch: continuous-claude/iteration-1/2025-11-15-be939873
✅ (1/1) PR #893 merged: Add unit tests for authentication module
🎉 Done with total cost: $0.042
```

## 🐝 Multi-Agent Swarm (v2.0)

Run multiple specialized agents that collaborate on complex tasks:

```bash
# Run a swarm with developer, tester, and reviewer agents
continuous-claude swarm -p "Build user authentication with JWT" -m pipeline

# Run with custom agents and auto-merge
continuous-claude swarm -p "Add API endpoints" -a "developer tester" --auto-merge

# Check swarm status
continuous-claude swarm --status
```

### Coordination Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Pipeline** | Sequential: dev → test → review | Standard feature development |
| **Parallel** | Concurrent independent work | Multi-component development |
| **Adaptive** | Dynamic switching based on progress | Complex projects |

### Available Personas

| Persona | Emoji | Role |
|---------|-------|------|
| `developer` | 🧑‍💻 | Feature implementation, bug fixes |
| `tester` | 🧪 | Test writing, coverage analysis |
| `reviewer` | 👁️ | Code review, quality gates |
| `documenter` | 📚 | Documentation, README updates |
| `security` | 🔒 | Security scanning, vulnerability fixes |

### Swarm Flags

| Flag | Description |
|------|-------------|
| `-p, --prompt` | Task prompt (required) |
| `-m, --mode` | Coordination mode: `pipeline`, `parallel`, `adaptive` |
| `-a, --agents` | Agent list (default: `"developer tester reviewer"`) |
| `--auto-merge` | Auto-merge PRs when approved |
| `--status` | Show current swarm status |

## 📊 Dashboard

Real-time monitoring web interface for swarm sessions:

```bash
# Start dashboard server
continuous-claude dashboard start 8000

# Check status
continuous-claude dashboard status

# Stop dashboard
continuous-claude dashboard stop
```

Open http://localhost:8000 in your browser.

Features:
- Live agent status and iteration tracking
- Task queue visualization (pending/in-progress/completed/failed)
- Real-time log streaming
- Cost tracking per agent and total
- WebSocket-powered updates

## 🧠 Learning System

Continuous Claude learns from failures to improve future attempts:

```bash
# Initialize learning database
continuous-claude learn init

# Install common pre-built insights
continuous-claude learn install-prebuilt

# View failure statistics
continuous-claude learn stats

# Parse CI logs for failures
continuous-claude learn parse-ci < ci.log
```

The system:
- Captures failures from CI logs and PR rejections
- Extracts patterns and solutions as "insights"
- Injects relevant insights into future prompts
- Tracks insight effectiveness over time

## 👁️ Automated Code Review

AI-powered code review with static analysis integration:

```bash
# Preview review (without submitting)
continuous-claude review 123

# Review and submit to GitHub
continuous-claude review 123 --submit

# Review with specific repo
continuous-claude review 123 -r owner/repo --submit

# Run static analysis only
continuous-claude review --analyze ./src
```

Includes:
- ESLint, Ruff, TypeScript static analysis
- Severity levels: blocker, major, minor, suggestion
- Automatic decision: APPROVE / REQUEST_CHANGES / COMMENT
- GitHub PR review API integration

## 🤖 Agent Management

View and manage available agent personas:

```bash
# List all available personas
continuous-claude agents list

# Get details for a specific persona
continuous-claude agents info developer
```

## 📚 Documentation

- [**User Guide**](docs/USER_GUIDE.md) - Practical guide with examples
- [**API Reference**](docs/API_REFERENCE.md) - Complete function reference
- [**Project Index**](docs/PROJECT_INDEX.md) - Architecture overview
- [**Cheatsheet**](docs/CHEATSHEET.md) - Quick reference card

## 📃 License

[MIT](./LICENSE)

**Original Project**: [Anand Chowdhary](https://anandchowdhary.com) - [continuous-claude](https://github.com/AnandChowdhary/continuous-claude)

**v2.0 Multi-Agent System**: [primadonna-gpters](https://github.com/primadonna-gpters/continuous-claude)
