# Multi-Agent Collaboration System Design Plan

> **Project**: Continuous Claude v2.0 - Multi-Agent Orchestration
> **Author**: Claude (AI Assistant)
> **Date**: 2025-12-10
> **Status**: Draft - Pending Approval

---

## Design Decisions (User Approved)

| 결정 항목 | 선택 | 근거 |
|----------|------|------|
| **Dashboard 기술 스택** | Python (FastAPI + Svelte) | 현대적, 빠른 개발, Python 생태계 활용 |
| **상태 저장소** | SQLite | 쿼리 가능, 동시성 지원, 단일 파일 |
| **머지 권한** | 설정 가능 (`--auto-merge` 플래그) | 유연성 제공 |

---

## Executive Summary

본 문서는 Continuous Claude를 **페르소나 기반 멀티에이전트 협업 시스템**으로 확장하기 위한 상세 구현 계획입니다.

### 핵심 목표
> 서로 다른 역할(페르소나)을 가진 AI 에이전트들이 **병렬로 작업하면서 상호 협력**하여 프로젝트를 완성하는 시스템 구축

### 통합 기능 (Ideas #3, #4, #5, #9)
| ID | 기능 | 설명 |
|----|------|------|
| #3 | 병렬 에이전트 조정 | 다중 에이전트 오케스트레이션 |
| #4 | 실패 학습 메커니즘 | 실패로부터 학습하여 다음 시도 개선 |
| #5 | 진행 상황 대시보드 | 실시간 모니터링 및 시각화 |
| #9 | 코드 리뷰 에이전트 | 자동 코드 리뷰 및 품질 검증 |

---

## 1. System Architecture

### 1.1 High-Level Architecture

```
                                    ┌─────────────────────────────────┐
                                    │         Orchestrator            │
                                    │   (continuous-claude-swarm)     │
                                    │                                 │
                                    │  ┌──────────────────────────┐  │
                                    │  │    Coordination Engine    │  │
                                    │  │  - Task Distribution      │  │
                                    │  │  - Conflict Resolution    │  │
                                    │  │  - Progress Tracking      │  │
                                    │  └──────────────────────────┘  │
                                    └─────────────┬───────────────────┘
                                                  │
                    ┌─────────────────────────────┼─────────────────────────────┐
                    │                             │                             │
                    ▼                             ▼                             ▼
    ┌───────────────────────────┐ ┌───────────────────────────┐ ┌───────────────────────────┐
    │     Developer Agent       │ │      Tester Agent         │ │     Reviewer Agent        │
    │     (🧑‍💻 Coder)           │ │     (🧪 QA)               │ │     (👁️ Critic)          │
    │                           │ │                           │ │                           │
    │  Persona:                 │ │  Persona:                 │ │  Persona:                 │
    │  - Feature implementation │ │  - Write tests            │ │  - Code review            │
    │  - Bug fixes              │ │  - Coverage analysis      │ │  - Quality gates          │
    │  - Refactoring            │ │  - Edge case testing      │ │  - Security audit         │
    │                           │ │                           │ │                           │
    │  Worktree: dev-agent      │ │  Worktree: test-agent     │ │  Worktree: review-agent   │
    └───────────────────────────┘ └───────────────────────────┘ └───────────────────────────┘
                    │                             │                             │
                    └─────────────────────────────┼─────────────────────────────┘
                                                  │
                                    ┌─────────────▼───────────────────┐
                                    │      Shared State Layer         │
                                    │                                 │
                                    │  ┌──────────┐ ┌──────────────┐ │
                                    │  │ Message  │ │   Learning   │ │
                                    │  │  Queue   │ │    Memory    │ │
                                    │  └──────────┘ └──────────────┘ │
                                    │  ┌──────────┐ ┌──────────────┐ │
                                    │  │ Progress │ │   Failure    │ │
                                    │  │  State   │ │    Log       │ │
                                    │  └──────────┘ └──────────────┘ │
                                    └─────────────────────────────────┘
                                                  │
                                    ┌─────────────▼───────────────────┐
                                    │      Dashboard Server           │
                                    │      (localhost:3000)           │
                                    │                                 │
                                    │  Real-time WebSocket Updates    │
                                    │  Agent Status / Progress        │
                                    │  Cost Tracking / Logs           │
                                    └─────────────────────────────────┘
```

### 1.2 Agent Communication Flow

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│  Developer  │     │   Tester    │     │  Reviewer   │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │  1. Implement     │                   │
       │  feature          │                   │
       │───────────────────┼───────────────────┤
       │                   │                   │
       │  2. Notify:       │                   │
       │  "Feature ready   │                   │
       │  for testing"     │                   │
       │──────────────────▶│                   │
       │                   │                   │
       │                   │  3. Write tests   │
       │                   │  & run coverage   │
       │                   │───────────────────┤
       │                   │                   │
       │  4. Feedback:     │                   │
       │  "Missing edge    │                   │
       │  case in func X"  │                   │
       │◀──────────────────│                   │
       │                   │                   │
       │  5. Fix edge case │                   │
       │───────────────────┼───────────────────┤
       │                   │                   │
       │                   │  6. Tests pass    │
       │                   │  Notify reviewer  │
       │                   │──────────────────▶│
       │                   │                   │
       │                   │                   │  7. Review code
       │                   │                   │  Check quality
       │                   │                   │────────────────
       │                   │                   │
       │  8. Review feedback: "Refactor method Y" │
       │◀──────────────────┼───────────────────│
       │                   │                   │
       │  9. Refactor      │                   │
       │───────────────────┼───────────────────┤
       │                   │                   │
       │                   │                   │  10. Approve
       │                   │                   │  → Merge PR
       ▼                   ▼                   ▼
```

---

## 2. Persona System Design

### 2.1 Persona Definition Schema

```yaml
# .continuous-claude/personas/developer.yaml
persona:
  id: developer
  name: "Developer Agent"
  emoji: "🧑‍💻"

  role: |
    You are a skilled software developer focused on implementing features
    and fixing bugs. You write clean, maintainable code following best practices.

  responsibilities:
    - Implement new features based on specifications
    - Fix bugs and address issues
    - Refactor code for better maintainability
    - Respond to code review feedback

  constraints:
    - Do not write tests (leave for Tester)
    - Do not merge PRs (leave for Reviewer)
    - Always document complex logic

  communication:
    listens_to:
      - reviewer.feedback
      - tester.failure_report
      - orchestrator.task_assignment
    publishes:
      - developer.feature_complete
      - developer.bug_fixed
      - developer.needs_clarification

  tools:
    allowed:
      - Read
      - Write
      - Edit
      - Bash(git)
      - Bash(npm)
      - Bash(cargo)
    denied:
      - Bash(gh pr merge)

  completion_signals:
    ready_for_test: "READY_FOR_TESTING"
    needs_review: "NEEDS_CODE_REVIEW"
    blocked: "BLOCKED_NEEDS_CLARIFICATION"
```

### 2.2 Pre-defined Personas

| Persona | Role | Primary Actions | Triggers Next |
|---------|------|-----------------|---------------|
| **🧑‍💻 Developer** | 기능 구현 | Write/Edit code | Tester |
| **🧪 Tester** | 테스트 작성 | Write tests, Run coverage | Reviewer (pass) / Developer (fail) |
| **👁️ Reviewer** | 코드 리뷰 | Review PRs, Quality check | Developer (changes) / Merge (approve) |
| **📚 Documenter** | 문서화 | Update docs, README | - |
| **🔒 Security** | 보안 감사 | Security scan, Fix vulns | Developer |
| **♻️ Refactorer** | 리팩토링 | Code cleanup, Optimization | Tester |

### 2.3 Custom Persona Creation

```bash
# 사용자 정의 페르소나 생성
continuous-claude persona create \
  --name "API Designer" \
  --role "Design and implement REST APIs" \
  --emoji "🌐" \
  --listens-to "developer.api_needed" \
  --publishes "api.schema_ready"
```

---

## 3. Coordination Engine

### 3.1 Task Distribution Strategy

```
┌─────────────────────────────────────────────────────────────┐
│                    Task Queue                                │
│  ┌─────────┬─────────┬─────────┬─────────┬─────────┐       │
│  │ Task 1  │ Task 2  │ Task 3  │ Task 4  │ Task 5  │       │
│  │ P:High  │ P:Med   │ P:High  │ P:Low   │ P:Med   │       │
│  │ T:Dev   │ T:Test  │ T:Dev   │ T:Doc   │ T:Review│       │
│  └─────────┴─────────┴─────────┴─────────┴─────────┘       │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│              Distribution Algorithm                          │
│                                                             │
│  1. Priority-based scheduling (High > Med > Low)            │
│  2. Persona affinity matching (Task Type → Persona)         │
│  3. Dependency resolution (Task 3 depends on Task 1)        │
│  4. Load balancing (spread across available agents)         │
│  5. Conflict detection (same file being edited)             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Conflict Resolution

```python
# Pseudo-code for conflict detection
class ConflictResolver:
    def detect_conflicts(self, agent_changes: List[Change]) -> List[Conflict]:
        """
        Detect potential conflicts between agent changes.
        """
        conflicts = []

        # Group changes by file
        changes_by_file = group_by(agent_changes, key='file_path')

        for file_path, changes in changes_by_file.items():
            if len(changes) > 1:
                # Multiple agents modifying same file
                conflicts.append(FileConflict(
                    file=file_path,
                    agents=[c.agent for c in changes],
                    resolution_strategy='sequential'  # or 'merge' or 'priority'
                ))

        return conflicts

    def resolve(self, conflict: Conflict) -> Resolution:
        """
        Resolution strategies:
        1. Sequential: One agent waits for another to finish
        2. Merge: Attempt automatic merge of changes
        3. Priority: Higher priority agent wins
        4. Human: Escalate to human decision
        """
        if conflict.can_auto_merge():
            return self.auto_merge(conflict)
        elif conflict.has_clear_priority():
            return self.priority_resolution(conflict)
        else:
            return self.sequential_execution(conflict)
```

### 3.3 Inter-Agent Messaging

```bash
# 메시지 디렉토리 구조
.continuous-claude/
├── messages/
│   ├── inbox/
│   │   ├── developer/      # Developer가 받는 메시지
│   │   ├── tester/         # Tester가 받는 메시지
│   │   └── reviewer/       # Reviewer가 받는 메시지
│   └── outbox/
│       └── pending/        # 발송 대기 메시지
├── state/
│   ├── progress.json       # 전체 진행 상황
│   ├── agents.json         # 에이전트 상태
│   └── tasks.json          # 태스크 큐
└── learning/
    ├── failures.json       # 실패 기록
    └── insights.json       # 학습된 인사이트
```

**메시지 포맷:**

```json
{
  "id": "msg-20251210-001",
  "from": "developer",
  "to": "tester",
  "type": "notification",
  "priority": "high",
  "timestamp": "2025-12-10T14:30:00Z",
  "subject": "Feature ready for testing",
  "body": {
    "feature": "user-authentication",
    "files_changed": [
      "src/auth/login.ts",
      "src/auth/middleware.ts"
    ],
    "branch": "continuous-claude/dev-agent/auth-feature",
    "notes": "Implemented JWT-based authentication. Edge cases to test: expired tokens, invalid signatures."
  },
  "metadata": {
    "iteration": 3,
    "cost_so_far": 0.45
  }
}
```

---

## 4. Failure Learning Mechanism (#4)

### 4.1 Failure Capture System

```
┌─────────────────────────────────────────────────────────────┐
│                    Failure Event                             │
│                                                             │
│  Type: CI_FAILURE                                           │
│  Agent: developer                                           │
│  Iteration: 5                                               │
│  Branch: continuous-claude/dev-agent/feature-x              │
│  PR: #123                                                   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │ CI Log Excerpt:                                      │   │
│  │                                                      │   │
│  │ FAIL src/auth/login.test.ts                         │   │
│  │   ● should reject expired tokens                    │   │
│  │     Expected: 401                                   │   │
│  │     Received: 200                                   │   │
│  │                                                      │   │
│  │ Test Suites: 1 failed, 23 passed                    │   │
│  │ Tests: 1 failed, 156 passed                         │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Failure Analyzer                             │
│                                                             │
│  1. Parse CI logs to extract failure reason                 │
│  2. Identify affected files and functions                   │
│  3. Correlate with recent changes                           │
│  4. Generate actionable insight                             │
│  5. Store in learning memory                                │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 Learning Memory Entry                        │
│                                                             │
│  {                                                          │
│    "id": "learn-001",                                       │
│    "type": "test_failure",                                  │
│    "pattern": "jwt_expiration_not_checked",                 │
│    "context": {                                             │
│      "file": "src/auth/login.ts",                          │
│      "function": "validateToken",                          │
│      "error": "Missing expiration check"                   │
│    },                                                       │
│    "solution": {                                            │
│      "description": "Add jwt.verify() with exp check",     │
│      "code_hint": "if (decoded.exp < Date.now()/1000)..."  │
│    },                                                       │
│    "success_rate_after": 0.95,                             │
│    "times_applied": 3                                       │
│  }                                                          │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Learning Prompt Injection

```bash
# 실패 학습이 적용된 프롬프트 구조

## CONTINUOUS WORKFLOW CONTEXT
...existing context...

## LEARNED INSIGHTS FROM PREVIOUS FAILURES

The following insights were learned from previous failures in this project:

### Insight #1: JWT Expiration Check
- **Pattern**: Test failures related to token expiration
- **Root Cause**: Missing expiration validation in validateToken()
- **Solution**: Always check `decoded.exp < Date.now()/1000` before accepting token
- **Files Affected**: src/auth/login.ts, src/auth/middleware.ts

### Insight #2: Database Connection Pool
- **Pattern**: Intermittent test failures with "connection refused"
- **Root Cause**: Pool exhaustion during parallel tests
- **Solution**: Use `poolSize: 5` in test config, add `afterAll(() => pool.end())`

## YOUR TASK
...original task prompt...
```

### 4.3 Failure Analysis Pipeline

```
┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐
│ Capture  │───▶│ Classify │───▶│ Analyze  │───▶│  Store   │
│          │    │          │    │          │    │          │
│ CI logs  │    │ Type:    │    │ Claude   │    │ JSON DB  │
│ PR state │    │ - Test   │    │ analyzes │    │ Memory   │
│ Git diff │    │ - Build  │    │ root     │    │ file     │
│          │    │ - Lint   │    │ cause    │    │          │
└──────────┘    │ - Review │    └──────────┘    └──────────┘
                └──────────┘
```

---

## 5. Progress Dashboard (#5)

### 5.1 Dashboard Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Dashboard Server                          │
│                    (Python FastAPI + Svelte)                 │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              WebSocket Server                        │   │
│  │                                                      │   │
│  │  Events:                                             │   │
│  │  - agent.status_changed                              │   │
│  │  - task.progress_updated                             │   │
│  │  - pr.created / pr.merged / pr.failed               │   │
│  │  - cost.updated                                      │   │
│  │  - message.sent                                      │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              REST API                                │   │
│  │                                                      │   │
│  │  GET  /api/agents          - List all agents        │   │
│  │  GET  /api/agents/:id      - Agent details          │   │
│  │  GET  /api/tasks           - Task queue             │   │
│  │  GET  /api/progress        - Overall progress       │   │
│  │  GET  /api/costs           - Cost breakdown         │   │
│  │  GET  /api/failures        - Failure history        │   │
│  │  POST /api/commands        - Send commands          │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    Web UI (React)                            │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Agent Cards                                         │   │
│  │  ┌──────────┐ ┌──────────┐ ┌──────────┐            │   │
│  │  │🧑‍💻 Dev    │ │🧪 Test   │ │👁️ Review │            │   │
│  │  │ Running  │ │ Waiting  │ │ Idle     │            │   │
│  │  │ Iter: 5  │ │ Queue: 2 │ │ PRs: 0   │            │   │
│  │  │ $0.45    │ │ $0.12    │ │ $0.08    │            │   │
│  │  └──────────┘ └──────────┘ └──────────┘            │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Progress Timeline                                   │   │
│  │  ═══════════════════════●═══════════○───────────    │   │
│  │  Started    Feature A    Testing    Review  Done    │   │
│  └─────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐   │
│  │  Live Log Stream                                     │   │
│  │  14:30:01 [dev] Starting iteration 5...             │   │
│  │  14:30:15 [dev] Implementing auth feature           │   │
│  │  14:31:02 [dev] ✅ Feature complete, notifying test │   │
│  │  14:31:03 [test] Received task, starting tests...   │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

### 5.2 SQLite Database Schema

```sql
-- .continuous-claude/state/swarm.db

-- 세션 정보
CREATE TABLE sessions (
    id TEXT PRIMARY KEY,
    started_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    prompt TEXT NOT NULL,
    total_cost REAL DEFAULT 0,
    status TEXT DEFAULT 'running' -- running, completed, failed
);

-- 에이전트 상태
CREATE TABLE agents (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id),
    persona TEXT NOT NULL,
    status TEXT DEFAULT 'idle', -- idle, running, waiting, error
    current_task TEXT,
    iteration INTEGER DEFAULT 0,
    cost REAL DEFAULT 0,
    worktree TEXT,
    last_activity TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 태스크 큐
CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id),
    agent_id TEXT REFERENCES agents(id),
    type TEXT NOT NULL,
    status TEXT DEFAULT 'pending', -- pending, in_progress, completed, failed
    priority INTEGER DEFAULT 5,
    payload JSON,
    result JSON,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    started_at TIMESTAMP,
    completed_at TIMESTAMP
);

-- 에이전트 간 메시지
CREATE TABLE messages (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id),
    from_agent TEXT NOT NULL,
    to_agent TEXT NOT NULL,
    type TEXT NOT NULL,
    subject TEXT,
    body JSON,
    read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 실패 학습 기록
CREATE TABLE failure_insights (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id),
    pattern TEXT NOT NULL,
    context JSON,
    solution JSON,
    success_rate REAL DEFAULT 0,
    times_applied INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- PR 기록
CREATE TABLE pull_requests (
    id TEXT PRIMARY KEY,
    session_id TEXT REFERENCES sessions(id),
    agent_id TEXT REFERENCES agents(id),
    pr_number INTEGER,
    title TEXT,
    status TEXT, -- open, merged, closed
    branch TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    merged_at TIMESTAMP
);

-- 인덱스
CREATE INDEX idx_agents_session ON agents(session_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_messages_to ON messages(to_agent, read);
CREATE INDEX idx_insights_pattern ON failure_insights(pattern);
```

### 5.3 Dashboard Data Model (Pydantic)

```python
# dashboard/backend/models/schemas.py

from pydantic import BaseModel
from datetime import datetime
from typing import Optional, List, Any

class AgentStatus(BaseModel):
    id: str
    persona: str
    status: str  # idle, running, waiting, error
    current_task: Optional[str]
    iteration: int
    cost: float
    worktree: str
    last_activity: Optional[datetime]

class TaskInfo(BaseModel):
    id: str
    type: str
    status: str
    priority: int
    agent_id: Optional[str]
    payload: dict
    created_at: datetime

class SessionInfo(BaseModel):
    id: str
    started_at: datetime
    prompt: str
    total_cost: float
    elapsed_time: float
    status: str

class TaskQueue(BaseModel):
    pending: List[TaskInfo]
    in_progress: List[TaskInfo]
    completed: List[TaskInfo]
    failed: List[TaskInfo]

class Message(BaseModel):
    id: str
    from_agent: str
    to_agent: str
    type: str
    subject: str
    body: dict
    created_at: datetime
    read: bool

class Metrics(BaseModel):
    success_rate: float
    avg_iteration_time: float
    total_prs: int
    merged_prs: int
    failed_prs: int

class DashboardState(BaseModel):
    session: SessionInfo
    agents: List[AgentStatus]
    tasks: TaskQueue
    recent_messages: List[Message]
    pending_messages: int
    metrics: Metrics
```

### 5.4 Notification Integration

```bash
# 지원할 알림 채널
--notify slack      # Slack webhook
--notify discord    # Discord webhook
--notify telegram   # Telegram bot
--notify email      # Email (SMTP)
--notify webhook    # Custom webhook URL

# 사용 예시
continuous-claude swarm \
  --agents "developer,tester,reviewer" \
  --prompt "Build auth system" \
  --dashboard \
  --notify slack \
  --slack-webhook "https://hooks.slack.com/..."
```

---

## 6. Code Review Agent (#9)

### 6.1 Review Agent Persona

```yaml
# .continuous-claude/personas/reviewer.yaml
persona:
  id: reviewer
  name: "Code Reviewer"
  emoji: "👁️"

  role: |
    You are a senior code reviewer with expertise in code quality,
    security, and best practices. You provide constructive feedback
    and approve code only when it meets quality standards.

  review_criteria:
    code_quality:
      - Clean code principles
      - SOLID principles adherence
      - DRY (Don't Repeat Yourself)
      - Appropriate naming conventions
      - Code complexity (cyclomatic)

    security:
      - Input validation
      - SQL injection prevention
      - XSS prevention
      - Authentication/Authorization
      - Sensitive data handling

    performance:
      - Algorithm efficiency
      - Memory usage
      - Database query optimization
      - Caching opportunities

    maintainability:
      - Documentation quality
      - Test coverage
      - Error handling
      - Logging adequacy

  review_actions:
    approve:
      condition: "All criteria pass, no blocking issues"
      action: "gh pr review --approve"

    request_changes:
      condition: "Blocking issues found"
      action: "gh pr review --request-changes"
      notify: ["developer"]

    comment:
      condition: "Non-blocking suggestions"
      action: "gh pr review --comment"

  severity_levels:
    blocker: "Must fix before merge"
    major: "Should fix, may approve with commitment"
    minor: "Nice to have, can merge as-is"
    suggestion: "Consider for future improvement"
```

### 6.2 Review Workflow

```
┌─────────────────────────────────────────────────────────────┐
│                    PR Ready for Review                       │
│                    (from Tester Agent)                       │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 1. Automated Checks                          │
│                                                             │
│  □ CI pipeline passed                                       │
│  □ Test coverage >= threshold                               │
│  □ No merge conflicts                                       │
│  □ Branch up-to-date with main                              │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 2. Static Analysis                           │
│                                                             │
│  Tools:                                                     │
│  - ESLint / Ruff (lint)                                     │
│  - TypeScript / MyPy (types)                                │
│  - SonarQube (quality)                                      │
│  - Snyk / npm audit (security)                              │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 3. AI-Powered Review                         │
│                                                             │
│  Claude reviews:                                            │
│  - Code logic and correctness                               │
│  - Architectural decisions                                  │
│  - Edge case handling                                       │
│  - Security implications                                    │
│  - Performance considerations                               │
└─────────────────────────────┬───────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                 4. Generate Review                           │
│                                                             │
│  Output:                                                    │
│  - Inline comments on specific lines                        │
│  - Overall review summary                                   │
│  - Decision: APPROVE / REQUEST_CHANGES / COMMENT            │
└─────────────────────────────┬───────────────────────────────┘
                              │
              ┌───────────────┼───────────────┐
              │               │               │
              ▼               ▼               ▼
        ┌─────────┐     ┌─────────┐     ┌─────────┐
        │ APPROVE │     │ REQUEST │     │ COMMENT │
        │         │     │ CHANGES │     │         │
        └────┬────┘     └────┬────┘     └────┬────┘
             │               │               │
             ▼               ▼               ▼
        Auto-merge      Notify Dev      Continue
                        for fixes       monitoring
```

### 6.3 Review Output Format

```markdown
## Code Review Summary

**PR**: #123 - Implement JWT Authentication
**Reviewer**: 👁️ Code Reviewer Agent
**Decision**: 🟡 REQUEST CHANGES

---

### Overview
The implementation correctly handles JWT token generation and validation.
However, there are security concerns that must be addressed before merging.

### Findings

#### 🔴 Blocker (1)
1. **[SECURITY]** Token expiration not validated
   - File: `src/auth/middleware.ts:45`
   - Issue: `jwt.verify()` called without checking `exp` claim
   - Suggested fix:
   ```typescript
   const decoded = jwt.verify(token, secret);
   if (decoded.exp && decoded.exp < Date.now() / 1000) {
     throw new TokenExpiredError();
   }
   ```

#### 🟠 Major (2)
1. **[QUALITY]** Duplicate code in login/register handlers
   - Files: `src/auth/login.ts:30-45`, `src/auth/register.ts:25-40`
   - Suggestion: Extract to shared `createSession()` function

2. **[SECURITY]** Password logged in debug mode
   - File: `src/auth/login.ts:15`
   - Issue: `logger.debug({ password })` exposes credentials

#### 🟢 Minor (3)
1. Magic number `3600` should be constant `TOKEN_EXPIRY_SECONDS`
2. Consider using `bcrypt.compare()` timing-safe comparison
3. Add JSDoc comments to public functions

---

### Required Actions
- [ ] Fix token expiration validation (Blocker)
- [ ] Remove password from logs (Major)
- [ ] Extract duplicate code (Major)

### Next Steps
After fixes are applied, please notify me for re-review.

---
*🤖 Generated by Code Reviewer Agent*
```

---

## 7. CLI Interface Design

### 7.1 New Commands

```bash
# Swarm mode - 멀티에이전트 오케스트레이션
continuous-claude swarm [options]

# Options
--agents <list>           # 사용할 에이전트 목록 (comma-separated)
--config <file>           # 스웜 설정 파일 경로
--coordination <mode>     # pipeline | parallel | adaptive
--dashboard               # 대시보드 서버 활성화
--dashboard-port <port>   # 대시보드 포트 (default: 3000)
--notify <channel>        # 알림 채널 (slack, discord, etc.)
--learn-from-failures     # 실패 학습 활성화
--max-concurrent <num>    # 최대 동시 에이전트 수
--auto-merge              # 리뷰 승인 시 자동 머지 (기본: 수동)
--db <path>               # SQLite 데이터베이스 경로 (default: .continuous-claude/state/swarm.db)
```

### 7.2 Usage Examples

```bash
# 예시 1: 기본 스웜 모드 (수동 머지)
continuous-claude swarm \
  --agents "developer,tester,reviewer" \
  --prompt "Implement user authentication with JWT" \
  --max-cost 20.00 \
  --dashboard

# 예시 1b: 자동 머지 활성화
continuous-claude swarm \
  --agents "developer,tester,reviewer" \
  --prompt "Add unit tests to utils module" \
  --max-runs 10 \
  --auto-merge \
  --learn-from-failures

# 예시 2: 파이프라인 모드 (순차 실행)
continuous-claude swarm \
  --agents "developer,tester,reviewer" \
  --coordination pipeline \
  --prompt "Add unit tests to auth module"

# 예시 3: 병렬 모드 (독립 작업)
continuous-claude swarm \
  --agents "developer:frontend,developer:backend,tester" \
  --coordination parallel \
  --prompt "Build REST API and React UI"

# 예시 4: 설정 파일 사용
continuous-claude swarm --config swarm.yaml

# 예시 5: 단일 에이전트에 페르소나 적용
continuous-claude \
  --persona reviewer \
  --prompt "Review all open PRs" \
  --max-runs 10

# 예시 6: 커스텀 페르소나 생성 및 사용
continuous-claude persona create \
  --name "API Specialist" \
  --from-template developer \
  --customize

continuous-claude swarm \
  --agents "api-specialist,tester" \
  --prompt "Design and implement REST endpoints"
```

### 7.3 Configuration File

```yaml
# swarm.yaml
version: "1.0"

session:
  name: "Auth System Implementation"
  prompt: |
    Build a complete JWT-based authentication system including:
    - User registration and login
    - Token refresh mechanism
    - Password reset flow
    - Role-based access control

limits:
  max_cost: 50.00
  max_duration: "4h"
  max_iterations_per_agent: 20

coordination:
  mode: adaptive  # pipeline | parallel | adaptive
  conflict_resolution: sequential
  review_required: true

agents:
  - id: developer
    persona: developer
    priority: high
    focus: "Core authentication logic"

  - id: frontend-dev
    persona: developer
    priority: medium
    focus: "Login/Register UI components"

  - id: tester
    persona: tester
    priority: medium
    triggers_on:
      - developer.feature_complete
      - frontend-dev.feature_complete

  - id: reviewer
    persona: reviewer
    priority: high
    triggers_on:
      - tester.tests_passed

learning:
  enabled: true
  failure_analysis: true
  share_insights: true  # Share learnings between agents

dashboard:
  enabled: true
  port: 3000

notifications:
  slack:
    webhook: "${SLACK_WEBHOOK_URL}"
    events:
      - pr.merged
      - pr.failed
      - session.complete
```

---

## 8. Implementation Phases

### Phase 1: Foundation (Week 1-2)

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 1: Core Infrastructure                                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ □ Implement message queue system                            │
│   - File-based message passing                              │
│   - Message format standardization                          │
│   - Inbox/Outbox directory structure                        │
│                                                             │
│ □ Create persona system                                     │
│   - YAML schema definition                                  │
│   - Persona loader and validator                            │
│   - Built-in personas (developer, tester, reviewer)         │
│                                                             │
│ □ Extend worktree management                                │
│   - Multi-worktree orchestration                            │
│   - Per-agent worktree isolation                            │
│   - Cleanup and synchronization                             │
│                                                             │
│ Deliverable: `continuous-claude --persona <name>` working   │
└─────────────────────────────────────────────────────────────┘
```

### Phase 2: Coordination Engine (Week 3-4)

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 2: Multi-Agent Coordination                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ □ Implement orchestrator process                            │
│   - Agent lifecycle management                              │
│   - Task distribution algorithm                             │
│   - Progress aggregation                                    │
│                                                             │
│ □ Build conflict resolution system                          │
│   - File-level conflict detection                           │
│   - Sequential/merge/priority strategies                    │
│   - Lock mechanism for shared resources                     │
│                                                             │
│ □ Create inter-agent communication                          │
│   - Event publishing (feature_complete, tests_passed, etc.) │
│   - Event subscription and handling                         │
│   - Timeout and retry logic                                 │
│                                                             │
│ Deliverable: `continuous-claude swarm --agents "..."` basic │
└─────────────────────────────────────────────────────────────┘
```

### Phase 3: Learning System (Week 5-6)

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 3: Failure Learning Mechanism                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ □ Implement failure capture                                 │
│   - CI log parsing and analysis                             │
│   - PR rejection reason extraction                          │
│   - Error classification system                             │
│                                                             │
│ □ Build learning memory                                     │
│   - JSON-based insight storage                              │
│   - Pattern matching for similar failures                   │
│   - Success rate tracking per insight                       │
│                                                             │
│ □ Create prompt injection system                            │
│   - Automatic insight injection                             │
│   - Context-aware filtering                                 │
│   - Insight relevance scoring                               │
│                                                             │
│ Deliverable: `--learn-from-failures` flag working           │
└─────────────────────────────────────────────────────────────┘
```

### Phase 4: Dashboard & Review (Week 7-8)

```
┌─────────────────────────────────────────────────────────────┐
│ Phase 4: Dashboard & Code Review Agent                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ □ Build dashboard server                                    │
│   - Node.js + Express backend                               │
│   - WebSocket real-time updates                             │
│   - REST API for state queries                              │
│                                                             │
│ □ Create dashboard UI                                       │
│   - React-based SPA                                         │
│   - Agent status cards                                      │
│   - Progress timeline                                       │
│   - Live log streaming                                      │
│   - Cost tracking visualization                             │
│                                                             │
│ □ Implement code review agent                               │
│   - Review criteria configuration                           │
│   - Static analysis integration                             │
│   - AI-powered review generation                            │
│   - GitHub PR review API integration                        │
│                                                             │
│ Deliverable: Full swarm mode with dashboard and review      │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. File Structure Changes

```
continuous-claude/
├── continuous_claude.sh          # 기존 스크립트 (유지)
├── continuous_claude_swarm.sh    # 새로운 스웜 오케스트레이터
├── lib/
│   ├── personas.sh               # 페르소나 관리 함수
│   ├── messaging.sh              # 에이전트 간 메시징
│   ├── coordination.sh           # 조정 엔진
│   ├── learning.sh               # 실패 학습 시스템
│   └── dashboard.sh              # 대시보드 서버 관리
├── personas/
│   ├── developer.yaml
│   ├── tester.yaml
│   ├── reviewer.yaml
│   ├── documenter.yaml
│   └── security.yaml
├── dashboard/
│   ├── backend/
│   │   ├── pyproject.toml
│   │   ├── main.py               # FastAPI + WebSocket 서버
│   │   ├── routes/
│   │   │   ├── agents.py
│   │   │   ├── tasks.py
│   │   │   └── websocket.py
│   │   ├── models/
│   │   │   └── schemas.py
│   │   └── db/
│   │       ├── database.py       # SQLite 연결
│   │       └── models.py         # SQLAlchemy 모델
│   └── frontend/
│       ├── package.json
│       ├── svelte.config.js
│       ├── src/
│       │   ├── App.svelte
│       │   ├── routes/
│       │   ├── lib/
│       │   │   ├── components/
│       │   │   │   ├── AgentCard.svelte
│       │   │   │   ├── ProgressTimeline.svelte
│       │   │   │   ├── LogStream.svelte
│       │   │   │   └── CostChart.svelte
│       │   │   └── stores/
│       │   │       └── agents.ts
│       │   └── app.css
│       └── static/
├── templates/
│   ├── swarm.yaml.example
│   └── persona.yaml.template
└── tests/
    ├── test_continuous_claude.bats
    ├── test_swarm.bats
    ├── test_personas.bats
    └── test_learning.bats
```

---

## 10. Success Metrics

### 10.1 Quantitative Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| PR Success Rate | > 80% | Merged PRs / Total PRs |
| Iteration Efficiency | < 5 avg | Iterations to complete task |
| Conflict Resolution | > 95% auto | Auto-resolved / Total conflicts |
| Learning Application | > 70% | Insights preventing repeat failures |
| Dashboard Latency | < 100ms | WebSocket update time |

### 10.2 Qualitative Metrics

| Metric | Target | Measurement |
|--------|--------|-------------|
| Code Quality | A/B grade | SonarQube rating |
| Test Coverage | > 80% | Coverage report |
| Security Issues | 0 critical | Snyk/npm audit |
| User Satisfaction | > 4.0/5.0 | Feedback survey |

---

## 11. Risk Assessment

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Agent conflicts causing data loss | Medium | High | File locking, atomic operations |
| Runaway costs | Low | High | Hard cost limits, alerts |
| Dashboard performance issues | Medium | Low | Pagination, sampling |
| Learning system generating bad advice | Low | Medium | Confidence scoring, human review |
| Complex coordination bugs | High | Medium | Extensive testing, gradual rollout |

---

## 12. Open Questions

### ✅ Resolved (User Decision)

1. ~~**Language Choice**: Dashboard를 Node.js로 할지 Bash 내장으로 할지?~~
   - **결정: Python (FastAPI + Svelte)**
   - 현대적 스택, 빠른 개발, Python 생태계 활용

2. ~~**State Persistence**: 파일 기반 vs SQLite vs Redis?~~
   - **결정: SQLite**
   - 쿼리 가능, 동시성 지원, 단일 파일로 관리 용이

3. ~~**Review Agent Authority**: 자동 머지 허용 vs 항상 사람 승인?~~
   - **결정: 설정 가능 (`--auto-merge` 플래그)**
   - 기본값은 사람 승인, 플래그로 자동 머지 활성화 가능

### ⏳ Remaining

4. **Agent Isolation**: Process vs Container?
   - Process: 단순, 빠른 시작
   - Container: 완전 격리, Docker 필요
   - **제안**: Phase 1에서는 Process로 시작, 추후 Container 옵션 추가

---

## Appendix A: Message Types

```yaml
message_types:
  # Task lifecycle
  task.assigned:
    from: orchestrator
    to: agent

  task.started:
    from: agent
    to: orchestrator

  task.completed:
    from: agent
    to: orchestrator

  task.failed:
    from: agent
    to: orchestrator

  # Feature lifecycle
  feature.implemented:
    from: developer
    to: tester

  feature.tested:
    from: tester
    to: reviewer

  feature.approved:
    from: reviewer
    to: orchestrator

  feature.changes_requested:
    from: reviewer
    to: developer

  # Test results
  test.passed:
    from: tester
    to: [developer, reviewer]

  test.failed:
    from: tester
    to: developer
    includes: [failure_reason, affected_files]

  # Review feedback
  review.comment:
    from: reviewer
    to: developer
    includes: [comments, severity]
```

---

## Appendix B: Example Session Log

```
$ continuous-claude swarm \
    --agents "developer,tester,reviewer" \
    --prompt "Build user authentication" \
    --max-cost 15.00 \
    --dashboard

🚀 Starting Continuous Claude Swarm v2.0
📋 Session: auth-impl-20251210-abc123
🎯 Goal: Build user authentication

🌐 Dashboard available at: http://localhost:3000

👥 Initializing agents...
   🧑‍💻 Developer Agent (worktree: dev-agent)
   🧪 Tester Agent (worktree: test-agent)
   👁️ Reviewer Agent (worktree: review-agent)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🔄 [developer] (1) Starting iteration...
🤖 [developer] Implementing JWT authentication...
✅ [developer] Feature complete: auth/login, auth/register
📨 [developer] → [tester]: Feature ready for testing
💰 [developer] Cost: $0.42

🔄 [tester] (1) Starting iteration...
🧪 [tester] Writing tests for auth module...
✅ [tester] Tests written: 15 test cases
🧪 [tester] Running coverage analysis...
❌ [tester] 2 tests failing: token expiration, password validation
📨 [tester] → [developer]: Test failures detected
💰 [tester] Cost: $0.28

📚 [learning] Captured failure insight: jwt_expiration_check

🔄 [developer] (2) Starting iteration...
📚 [developer] Applying learned insight: jwt_expiration_check
🔧 [developer] Fixing token expiration issue...
✅ [developer] Fixes applied
📨 [developer] → [tester]: Fixes ready for re-test
💰 [developer] Cost: $0.31

🔄 [tester] (2) Starting iteration...
🧪 [tester] Re-running tests...
✅ [tester] All 15 tests passing
✅ [tester] Coverage: 87%
📨 [tester] → [reviewer]: Tests passed, ready for review
💰 [tester] Cost: $0.15

🔄 [reviewer] (1) Starting iteration...
👁️ [reviewer] Reviewing PR #45...
📝 [reviewer] 2 comments added (1 major, 1 minor)
📨 [reviewer] → [developer]: Changes requested
💰 [reviewer] Cost: $0.22

🔄 [developer] (3) Starting iteration...
🔧 [developer] Addressing review feedback...
✅ [developer] Changes applied
📨 [developer] → [reviewer]: Ready for re-review
💰 [developer] Cost: $0.25

🔄 [reviewer] (2) Starting iteration...
👁️ [reviewer] Re-reviewing PR #45...
✅ [reviewer] APPROVED
🔀 [reviewer] Merging PR #45...
✅ [reviewer] PR #45 merged: Implement JWT authentication
💰 [reviewer] Cost: $0.18

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

🎉 Session Complete!

📊 Summary:
   Total iterations: 8
   PRs created: 1
   PRs merged: 1
   Total cost: $1.81
   Duration: 12m 34s

📚 Insights learned: 1
   - jwt_expiration_check (applied successfully)

👥 Agent breakdown:
   🧑‍💻 Developer: 3 iterations, $0.98
   🧪 Tester: 2 iterations, $0.43
   👁️ Reviewer: 2 iterations, $0.40
```

---

*Document Version: 1.0*
*Last Updated: 2025-12-10*
