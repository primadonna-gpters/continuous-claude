"""
Pydantic schemas for API request/response validation.
"""
from datetime import datetime
from typing import Optional, Any
from pydantic import BaseModel, ConfigDict


# =============================================================================
# Session Schemas
# =============================================================================

class SessionBase(BaseModel):
    prompt: str
    status: str = "running"


class SessionCreate(SessionBase):
    id: str


class SessionInfo(SessionBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    started_at: datetime
    total_cost: float
    elapsed_time: Optional[float] = None


# =============================================================================
# Agent Schemas
# =============================================================================

class AgentBase(BaseModel):
    persona: str
    status: str = "idle"


class AgentCreate(AgentBase):
    id: str
    session_id: str
    worktree: Optional[str] = None


class AgentStatus(AgentBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    current_task: Optional[str] = None
    iteration: int = 0
    cost: float = 0.0
    worktree: Optional[str] = None
    last_activity: Optional[datetime] = None


class AgentUpdate(BaseModel):
    status: Optional[str] = None
    current_task: Optional[str] = None
    iteration: Optional[int] = None
    cost: Optional[float] = None


# =============================================================================
# Task Schemas
# =============================================================================

class TaskBase(BaseModel):
    type: str
    priority: int = 5
    payload: Optional[dict[str, Any]] = None


class TaskCreate(TaskBase):
    id: str
    session_id: str
    agent_id: Optional[str] = None


class TaskInfo(TaskBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    status: str
    agent_id: Optional[str] = None
    result: Optional[dict[str, Any]] = None
    created_at: datetime
    started_at: Optional[datetime] = None
    completed_at: Optional[datetime] = None


class TaskUpdate(BaseModel):
    status: Optional[str] = None
    agent_id: Optional[str] = None
    result: Optional[dict[str, Any]] = None


class TaskQueue(BaseModel):
    pending: list[TaskInfo] = []
    in_progress: list[TaskInfo] = []
    completed: list[TaskInfo] = []
    failed: list[TaskInfo] = []


# =============================================================================
# Message Schemas
# =============================================================================

class MessageBase(BaseModel):
    from_agent: str
    to_agent: str
    type: str
    subject: Optional[str] = None
    body: Optional[dict[str, Any]] = None


class MessageCreate(MessageBase):
    id: str
    session_id: str


class MessageInfo(MessageBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    read: bool = False
    created_at: datetime


# =============================================================================
# Insight Schemas
# =============================================================================

class InsightBase(BaseModel):
    pattern: str
    failure_type: str
    description: str
    solution: str
    root_cause: Optional[str] = None
    code_hint: Optional[str] = None


class InsightCreate(InsightBase):
    session_id: Optional[str] = None


class InsightInfo(InsightBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    confidence: float = 0.5
    times_applied: int = 0
    times_successful: int = 0
    created_at: datetime
    updated_at: datetime


# =============================================================================
# Pull Request Schemas
# =============================================================================

class PullRequestBase(BaseModel):
    pr_number: Optional[int] = None
    title: Optional[str] = None
    status: Optional[str] = None
    branch: Optional[str] = None


class PullRequestCreate(PullRequestBase):
    id: str
    session_id: str
    agent_id: Optional[str] = None


class PullRequestInfo(PullRequestBase):
    model_config = ConfigDict(from_attributes=True)

    id: str
    agent_id: Optional[str] = None
    created_at: datetime
    merged_at: Optional[datetime] = None


# =============================================================================
# Log Schemas
# =============================================================================

class LogEntryBase(BaseModel):
    level: str = "info"
    message: str
    data: Optional[dict[str, Any]] = None


class LogEntryCreate(LogEntryBase):
    session_id: str
    agent_id: Optional[str] = None


class LogEntryInfo(LogEntryBase):
    model_config = ConfigDict(from_attributes=True)

    id: int
    session_id: str
    agent_id: Optional[str] = None
    created_at: datetime


# =============================================================================
# Dashboard Composite Schemas
# =============================================================================

class Metrics(BaseModel):
    success_rate: float = 0.0
    avg_iteration_time: float = 0.0
    total_prs: int = 0
    merged_prs: int = 0
    failed_prs: int = 0
    total_cost: float = 0.0


class DashboardState(BaseModel):
    session: Optional[SessionInfo] = None
    agents: list[AgentStatus] = []
    tasks: TaskQueue = TaskQueue()
    recent_messages: list[MessageInfo] = []
    pending_messages: int = 0
    metrics: Metrics = Metrics()
    recent_logs: list[LogEntryInfo] = []


# =============================================================================
# WebSocket Event Schemas
# =============================================================================

class WebSocketEvent(BaseModel):
    event: str
    data: dict[str, Any]
    timestamp: datetime = datetime.utcnow()


class AgentStatusEvent(BaseModel):
    agent_id: str
    status: str
    iteration: Optional[int] = None
    cost: Optional[float] = None


class TaskProgressEvent(BaseModel):
    task_id: str
    status: str
    progress: Optional[float] = None


class MessageEvent(BaseModel):
    from_agent: str
    to_agent: str
    type: str
    subject: Optional[str] = None
