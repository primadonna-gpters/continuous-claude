"""
Task queue management API routes.
"""
from datetime import datetime
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession

from db.database import get_session
from db.models import Task, Session
from models.schemas import TaskInfo, TaskCreate, TaskUpdate, TaskQueue

router = APIRouter(prefix="/tasks", tags=["tasks"])


@router.get("", response_model=list[TaskInfo])
async def list_tasks(
    session_id: str | None = None,
    status: str | None = None,
    agent_id: str | None = None,
    db: AsyncSession = Depends(get_session),
):
    """List all tasks with optional filters."""
    query = select(Task)

    if session_id:
        query = query.where(Task.session_id == session_id)
    if status:
        query = query.where(Task.status == status)
    if agent_id:
        query = query.where(Task.agent_id == agent_id)

    query = query.order_by(Task.priority.desc(), Task.created_at)

    result = await db.execute(query)
    tasks = result.scalars().all()
    return tasks


@router.get("/queue", response_model=TaskQueue)
async def get_task_queue(
    session_id: str | None = None,
    db: AsyncSession = Depends(get_session),
):
    """Get tasks organized by status."""
    base_query = select(Task)
    if session_id:
        base_query = base_query.where(Task.session_id == session_id)

    result = await db.execute(base_query.order_by(Task.priority.desc(), Task.created_at))
    all_tasks = result.scalars().all()

    queue = TaskQueue()
    for task in all_tasks:
        task_info = TaskInfo.model_validate(task)
        if task.status == "pending":
            queue.pending.append(task_info)
        elif task.status == "in_progress":
            queue.in_progress.append(task_info)
        elif task.status == "completed":
            queue.completed.append(task_info)
        elif task.status == "failed":
            queue.failed.append(task_info)

    return queue


@router.get("/{task_id}", response_model=TaskInfo)
async def get_task(
    task_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Get task details by ID."""
    result = await db.execute(select(Task).where(Task.id == task_id))
    task = result.scalar_one_or_none()

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    return task


@router.post("", response_model=TaskInfo)
async def create_task(
    task_data: TaskCreate,
    db: AsyncSession = Depends(get_session),
):
    """Create a new task."""
    # Check if session exists
    result = await db.execute(select(Session).where(Session.id == task_data.session_id))
    session = result.scalar_one_or_none()

    if not session:
        raise HTTPException(status_code=404, detail="Session not found")

    task = Task(
        id=task_data.id,
        session_id=task_data.session_id,
        agent_id=task_data.agent_id,
        type=task_data.type,
        priority=task_data.priority,
        payload=task_data.payload,
        status="pending",
        created_at=datetime.utcnow(),
    )

    db.add(task)
    await db.commit()
    await db.refresh(task)

    return task


@router.patch("/{task_id}", response_model=TaskInfo)
async def update_task(
    task_id: str,
    update_data: TaskUpdate,
    db: AsyncSession = Depends(get_session),
):
    """Update task status and properties."""
    result = await db.execute(select(Task).where(Task.id == task_id))
    task = result.scalar_one_or_none()

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    update_dict = update_data.model_dump(exclude_unset=True)

    # Handle status transitions
    if "status" in update_dict:
        new_status = update_dict["status"]
        if new_status == "in_progress" and task.started_at is None:
            task.started_at = datetime.utcnow()
        elif new_status in ("completed", "failed") and task.completed_at is None:
            task.completed_at = datetime.utcnow()

    for field, value in update_dict.items():
        setattr(task, field, value)

    await db.commit()
    await db.refresh(task)

    return task


@router.delete("/{task_id}")
async def delete_task(
    task_id: str,
    db: AsyncSession = Depends(get_session),
):
    """Delete a task."""
    result = await db.execute(select(Task).where(Task.id == task_id))
    task = result.scalar_one_or_none()

    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    await db.delete(task)
    await db.commit()

    return {"status": "deleted", "task_id": task_id}


@router.get("/stats/summary")
async def get_task_stats(
    session_id: str | None = None,
    db: AsyncSession = Depends(get_session),
):
    """Get task queue statistics."""
    base_query = select(Task)
    if session_id:
        base_query = base_query.where(Task.session_id == session_id)

    # Count by status
    result = await db.execute(base_query)
    all_tasks = result.scalars().all()

    stats = {
        "total": len(all_tasks),
        "pending": sum(1 for t in all_tasks if t.status == "pending"),
        "in_progress": sum(1 for t in all_tasks if t.status == "in_progress"),
        "completed": sum(1 for t in all_tasks if t.status == "completed"),
        "failed": sum(1 for t in all_tasks if t.status == "failed"),
    }

    # Calculate average completion time for completed tasks
    completed_tasks = [t for t in all_tasks if t.status == "completed" and t.started_at and t.completed_at]
    if completed_tasks:
        avg_time = sum((t.completed_at - t.started_at).total_seconds() for t in completed_tasks) / len(completed_tasks)
        stats["avg_completion_time_seconds"] = avg_time
    else:
        stats["avg_completion_time_seconds"] = 0

    return stats
