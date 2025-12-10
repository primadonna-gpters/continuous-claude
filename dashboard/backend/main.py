"""
Continuous Claude Dashboard - FastAPI Backend

Real-time monitoring dashboard for multi-agent swarm orchestration.
"""
import os
from contextlib import asynccontextmanager
from datetime import datetime
from fastapi import FastAPI, Depends, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from db.database import init_db, close_db, get_session
from db.models import Session, Agent, Task, Message, PullRequest, LogEntry
from models.schemas import (
    SessionInfo, SessionCreate, DashboardState, Metrics,
    AgentStatus, TaskInfo, TaskQueue, MessageInfo, LogEntryInfo
)
from routes import agents, tasks, websocket


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifespan handler."""
    # Startup
    await init_db()
    yield
    # Shutdown
    await close_db()


app = FastAPI(
    title="Continuous Claude Dashboard",
    description="Real-time monitoring dashboard for multi-agent swarm orchestration",
    version="0.1.0",
    lifespan=lifespan,
)

# CORS configuration
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "http://localhost:3000",
        "http://localhost:5173",
        "http://127.0.0.1:3000",
        "http://127.0.0.1:5173",
    ],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include routers
app.include_router(agents.router, prefix="/api")
app.include_router(tasks.router, prefix="/api")
app.include_router(websocket.router)


# =============================================================================
# Session Management Endpoints
# =============================================================================

@app.get("/api/sessions", response_model=list[SessionInfo])
async def list_sessions(
    status: str | None = None,
    limit: int = 10,
    db: AsyncSession = Depends(get_session),
):
    """List recent sessions."""
    query = select(Session)
    if status:
        query = query.where(Session.status == status)
    query = query.order_by(Session.started_at.desc()).limit(limit)

    result = await db.execute(query)
    sessions = result.scalars().all()

    return [
        SessionInfo(
            id=s.id,
            started_at=s.started_at,
            prompt=s.prompt,
            total_cost=s.total_cost,
            status=s.status,
            elapsed_time=(datetime.utcnow() - s.started_at).total_seconds() if s.started_at else 0,
        )
        for s in sessions
    ]


@app.get("/api/sessions/{session_id}", response_model=SessionInfo)
async def get_session_info(
    session_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get session details."""
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    return SessionInfo(
        id=session.id,
        started_at=session.started_at,
        prompt=session.prompt,
        total_cost=session.total_cost,
        status=session.status,
        elapsed_time=(datetime.utcnow() - session.started_at).total_seconds() if session.started_at else 0,
    )


@app.post("/api/sessions", response_model=SessionInfo)
async def create_session(
    session_data: SessionCreate,
    db: AsyncSession = Depends(get_session),
):
    """Create a new session."""
    session = Session(
        id=session_data.id,
        prompt=session_data.prompt,
        status=session_data.status,
        started_at=datetime.utcnow(),
    )

    db.add(session)
    await db.commit()
    await db.refresh(session)

    return SessionInfo(
        id=session.id,
        started_at=session.started_at,
        prompt=session.prompt,
        total_cost=session.total_cost,
        status=session.status,
        elapsed_time=0,
    )


@app.patch("/api/sessions/{session_id}")
async def update_session(
    session_id: str,
    status: str | None = None,
    total_cost: float | None = None,
    db: AsyncSession = Depends(get_session),
):
    """Update session status and cost."""
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    if status:
        session.status = status
    if total_cost is not None:
        session.total_cost = total_cost

    await db.commit()

    return {"status": "updated", "session_id": session_id}


# =============================================================================
# Dashboard State Endpoint
# =============================================================================

@app.get("/api/dashboard/{session_id}", response_model=DashboardState)
async def get_dashboard_state(
    session_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get complete dashboard state for a session."""
    # Get session
    result = await db.execute(select(Session).where(Session.id == session_id))
    session = result.scalar_one_or_none()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    # Get agents
    result = await db.execute(
        select(Agent).where(Agent.session_id == session_id).order_by(Agent.created_at)
    )
    agents_list = [AgentStatus.model_validate(a) for a in result.scalars().all()]

    # Get tasks organized by status
    result = await db.execute(
        select(Task).where(Task.session_id == session_id).order_by(Task.priority.desc(), Task.created_at)
    )
    all_tasks = result.scalars().all()

    task_queue = TaskQueue()
    for task in all_tasks:
        task_info = TaskInfo.model_validate(task)
        if task.status == "pending":
            task_queue.pending.append(task_info)
        elif task.status == "in_progress":
            task_queue.in_progress.append(task_info)
        elif task.status == "completed":
            task_queue.completed.append(task_info)
        elif task.status == "failed":
            task_queue.failed.append(task_info)

    # Get recent messages
    result = await db.execute(
        select(Message)
        .where(Message.session_id == session_id)
        .order_by(Message.created_at.desc())
        .limit(20)
    )
    recent_messages = [MessageInfo.model_validate(m) for m in result.scalars().all()]

    # Count unread messages
    result = await db.execute(
        select(func.count(Message.id))
        .where(Message.session_id == session_id)
        .where(Message.read == False)
    )
    pending_messages = result.scalar() or 0

    # Get recent logs
    result = await db.execute(
        select(LogEntry)
        .where(LogEntry.session_id == session_id)
        .order_by(LogEntry.created_at.desc())
        .limit(50)
    )
    recent_logs = [LogEntryInfo.model_validate(log) for log in result.scalars().all()]

    # Calculate metrics
    result = await db.execute(
        select(PullRequest).where(PullRequest.session_id == session_id)
    )
    prs = result.scalars().all()
    total_prs = len(prs)
    merged_prs = sum(1 for pr in prs if pr.status == "merged")
    failed_prs = sum(1 for pr in prs if pr.status == "closed" and pr.merged_at is None)

    completed_tasks = [t for t in all_tasks if t.status == "completed"]
    failed_tasks = [t for t in all_tasks if t.status == "failed"]
    total_tasks = len(completed_tasks) + len(failed_tasks)
    success_rate = len(completed_tasks) / total_tasks if total_tasks > 0 else 0

    # Calculate average iteration time
    avg_time = 0
    if completed_tasks:
        times = [
            (t.completed_at - t.started_at).total_seconds()
            for t in completed_tasks
            if t.started_at and t.completed_at
        ]
        avg_time = sum(times) / len(times) if times else 0

    metrics = Metrics(
        success_rate=success_rate,
        avg_iteration_time=avg_time,
        total_prs=total_prs,
        merged_prs=merged_prs,
        failed_prs=failed_prs,
        total_cost=session.total_cost,
    )

    return DashboardState(
        session=SessionInfo(
            id=session.id,
            started_at=session.started_at,
            prompt=session.prompt,
            total_cost=session.total_cost,
            status=session.status,
            elapsed_time=(datetime.utcnow() - session.started_at).total_seconds() if session.started_at else 0,
        ),
        agents=agents_list,
        tasks=task_queue,
        recent_messages=recent_messages,
        pending_messages=pending_messages,
        metrics=metrics,
        recent_logs=recent_logs,
    )


# =============================================================================
# Log Endpoints
# =============================================================================

@app.get("/api/logs/{session_id}", response_model=list[LogEntryInfo])
async def get_logs(
    session_id: str,
    agent_id: str | None = None,
    level: str | None = None,
    limit: int = 100,
    db: AsyncSession = Depends(get_session),
):
    """Get log entries for a session."""
    query = select(LogEntry).where(LogEntry.session_id == session_id)

    if agent_id:
        query = query.where(LogEntry.agent_id == agent_id)
    if level:
        query = query.where(LogEntry.level == level)

    query = query.order_by(LogEntry.created_at.desc()).limit(limit)

    result = await db.execute(query)
    return [LogEntryInfo.model_validate(log) for log in result.scalars().all()]


@app.post("/api/logs")
async def create_log_entry(
    session_id: str,
    level: str,
    message: str,
    agent_id: str | None = None,
    data: dict | None = None,
    db: AsyncSession = Depends(get_session),
):
    """Create a log entry."""
    log_entry = LogEntry(
        session_id=session_id,
        agent_id=agent_id,
        level=level,
        message=message,
        data=data,
        created_at=datetime.utcnow(),
    )

    db.add(log_entry)
    await db.commit()

    # Emit WebSocket event
    from routes.websocket import emit_log_entry
    await emit_log_entry(session_id, agent_id, level, message, data)

    return {"status": "created"}


# =============================================================================
# Health Check
# =============================================================================

@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {
        "status": "healthy",
        "timestamp": datetime.utcnow().isoformat(),
    }


@app.get("/")
async def root():
    """Root endpoint with API information."""
    return {
        "name": "Continuous Claude Dashboard API",
        "version": "0.1.0",
        "docs": "/docs",
        "health": "/health",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=int(os.environ.get("PORT", 8000)),
        reload=True,
    )
