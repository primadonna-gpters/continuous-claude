"""
SQLAlchemy ORM models for the dashboard database.
"""
from datetime import datetime
from sqlalchemy import Column, Integer, String, Float, Boolean, DateTime, Text, ForeignKey, JSON
from sqlalchemy.orm import relationship
from .database import Base


class Session(Base):
    """Swarm session information."""
    __tablename__ = "sessions"

    id = Column(String, primary_key=True)
    started_at = Column(DateTime, default=datetime.utcnow)
    prompt = Column(Text, nullable=False)
    total_cost = Column(Float, default=0.0)
    status = Column(String, default="running")  # running, completed, failed

    # Relationships
    agents = relationship("Agent", back_populates="session", cascade="all, delete-orphan")
    tasks = relationship("Task", back_populates="session", cascade="all, delete-orphan")
    messages = relationship("Message", back_populates="session", cascade="all, delete-orphan")
    pull_requests = relationship("PullRequest", back_populates="session", cascade="all, delete-orphan")


class Agent(Base):
    """Agent state and information."""
    __tablename__ = "agents"

    id = Column(String, primary_key=True)
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    persona = Column(String, nullable=False)
    status = Column(String, default="idle")  # idle, running, waiting, error
    current_task = Column(String, nullable=True)
    iteration = Column(Integer, default=0)
    cost = Column(Float, default=0.0)
    worktree = Column(String, nullable=True)
    last_activity = Column(DateTime, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    session = relationship("Session", back_populates="agents")
    tasks = relationship("Task", back_populates="agent")
    pull_requests = relationship("PullRequest", back_populates="agent")


class Task(Base):
    """Task queue items."""
    __tablename__ = "tasks"

    id = Column(String, primary_key=True)
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    agent_id = Column(String, ForeignKey("agents.id"), nullable=True)
    type = Column(String, nullable=False)
    status = Column(String, default="pending")  # pending, in_progress, completed, failed
    priority = Column(Integer, default=5)
    payload = Column(JSON, nullable=True)
    result = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    started_at = Column(DateTime, nullable=True)
    completed_at = Column(DateTime, nullable=True)

    # Relationships
    session = relationship("Session", back_populates="tasks")
    agent = relationship("Agent", back_populates="tasks")


class Message(Base):
    """Inter-agent messages."""
    __tablename__ = "messages"

    id = Column(String, primary_key=True)
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    from_agent = Column(String, nullable=False)
    to_agent = Column(String, nullable=False)
    type = Column(String, nullable=False)
    subject = Column(String, nullable=True)
    body = Column(JSON, nullable=True)
    read = Column(Boolean, default=False)
    created_at = Column(DateTime, default=datetime.utcnow)

    # Relationships
    session = relationship("Session", back_populates="messages")


class FailureInsight(Base):
    """Learned failure insights."""
    __tablename__ = "failure_insights"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String, ForeignKey("sessions.id"), nullable=True)
    pattern = Column(String, unique=True, nullable=False)
    failure_type = Column(String, nullable=False)
    description = Column(Text, nullable=False)
    root_cause = Column(Text, nullable=True)
    solution = Column(Text, nullable=False)
    code_hint = Column(Text, nullable=True)
    confidence = Column(Float, default=0.5)
    times_applied = Column(Integer, default=0)
    times_successful = Column(Integer, default=0)
    created_at = Column(DateTime, default=datetime.utcnow)
    updated_at = Column(DateTime, default=datetime.utcnow, onupdate=datetime.utcnow)


class PullRequest(Base):
    """Pull request tracking."""
    __tablename__ = "pull_requests"

    id = Column(String, primary_key=True)
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    agent_id = Column(String, ForeignKey("agents.id"), nullable=True)
    pr_number = Column(Integer, nullable=True)
    title = Column(String, nullable=True)
    status = Column(String, nullable=True)  # open, merged, closed
    branch = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
    merged_at = Column(DateTime, nullable=True)

    # Relationships
    session = relationship("Session", back_populates="pull_requests")
    agent = relationship("Agent", back_populates="pull_requests")


class LogEntry(Base):
    """Real-time log entries for streaming."""
    __tablename__ = "log_entries"

    id = Column(Integer, primary_key=True, autoincrement=True)
    session_id = Column(String, ForeignKey("sessions.id"), nullable=False)
    agent_id = Column(String, nullable=True)
    level = Column(String, default="info")  # info, warning, error, debug
    message = Column(Text, nullable=False)
    data = Column(JSON, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)
