"""
Agent management API routes.
"""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from db.database import get_session
from db.models import Agent, Session
from models.schemas import AgentStatus, AgentCreate, AgentUpdate

router = APIRouter(prefix="/agents", tags=["agents"])


@router.get("", response_model=list[AgentStatus])
async def list_agents(
    session_id: str | None = None,
    db: AsyncSession = Depends(get_session),
):
    """List all agents, optionally filtered by session."""
    query = select(Agent)
    if session_id:
        query = query.where(Agent.session_id == session_id)
    query = query.order_by(Agent.created_at)

    result = await db.execute(query)
    agents = result.scalars().all()
    return agents


@router.get("/{agent_id}", response_model=AgentStatus)
async def get_agent(
    agent_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get agent details by ID."""
    result = await db.execute(select(Agent).where(Agent.id == agent_id))
    agent = result.scalar_one_or_none()

    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    return agent


@router.post("", response_model=AgentStatus)
async def create_agent(
    agent_data: AgentCreate,
    db: AsyncSession = Depends(get_session),
):
    """Create a new agent."""
    # Check if session exists
    result = await db.execute(select(Session).where(Session.id == agent_data.session_id))
    session = result.scalar_one_or_none()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    agent = Agent(
        id=agent_data.id,
        session_id=agent_data.session_id,
        persona=agent_data.persona,
        status=agent_data.status,
        worktree=agent_data.worktree,
        created_at=datetime.utcnow(),
    )

    db.add(agent)
    await db.commit()
    await db.refresh(agent)

    return agent


@router.patch("/{agent_id}", response_model=AgentStatus)
async def update_agent(
    agent_id: str,
    update_data: AgentUpdate,
    db: AsyncSession = Depends(get_session),
):
    """Update agent status and properties."""
    result = await db.execute(select(Agent).where(Agent.id == agent_id))
    agent = result.scalar_one_or_none()

    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    update_dict = update_data.model_dump(exclude_unset=True)
    for field, value in update_dict.items():
        setattr(agent, field, value)

    agent.last_activity = datetime.utcnow()

    await db.commit()
    await db.refresh(agent)

    return agent


@router.delete("/{agent_id}")
async def delete_agent(
    agent_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Delete an agent."""
    result = await db.execute(select(Agent).where(Agent.id == agent_id))
    agent = result.scalar_one_or_none()

    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    await db.delete(agent)
    await db.commit()

    return {"status": "deleted", "agent_id": agent_id}


@router.get("/{agent_id}/stats")
async def get_agent_stats(
    agent_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get agent statistics."""
    result = await db.execute(select(Agent).where(Agent.id == agent_id))
    agent = result.scalar_one_or_none()

    if not agent:
        raise HTTPException(status_code=404, detail="Agent not found")

    return {
        "agent_id": agent_id,
        "persona": agent.persona,
        "total_iterations": agent.iteration,
        "total_cost": agent.cost,
        "status": agent.status,
        "uptime": (datetime.utcnow() - agent.created_at).total_seconds() if agent.created_at else 0,
    }
