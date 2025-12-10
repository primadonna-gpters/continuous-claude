"""
WebSocket handler for real-time dashboard updates.
"""
import asyncio
import json
from datetime import datetime
from typing import Any
from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

router = APIRouter(tags=["websocket"])


class ConnectionManager:
    """Manages WebSocket connections for real-time updates."""

    def __init__(self):
        self.active_connections: list[WebSocket] = []
        self.session_connections: dict[str, list[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, session_id: str | None = None):
        """Accept a new WebSocket connection."""
        await websocket.accept()
        self.active_connections.append(websocket)

        if session_id:
            if session_id not in self.session_connections:
                self.session_connections[session_id] = []
            self.session_connections[session_id].append(websocket)

    def disconnect(self, websocket: WebSocket, session_id: str | None = None):
        """Remove a WebSocket connection."""
        if websocket in self.active_connections:
            self.active_connections.remove(websocket)

        if session_id and session_id in self.session_connections:
            if websocket in self.session_connections[session_id]:
                self.session_connections[session_id].remove(websocket)
            if not self.session_connections[session_id]:
                del self.session_connections[session_id]

    async def broadcast(self, event: str, data: dict[str, Any]):
        """Broadcast event to all connected clients."""
        message = json.dumps({
            "event": event,
            "data": data,
            "timestamp": datetime.utcnow().isoformat(),
        })

        disconnected = []
        for connection in self.active_connections:
            try:
                await connection.send_text(message)
            except Exception:
                disconnected.append(connection)

        # Clean up disconnected clients
        for conn in disconnected:
            self.disconnect(conn)

    async def broadcast_to_session(self, session_id: str, event: str, data: dict[str, Any]):
        """Broadcast event to clients watching a specific session."""
        if session_id not in self.session_connections:
            return

        message = json.dumps({
            "event": event,
            "data": data,
            "session_id": session_id,
            "timestamp": datetime.utcnow().isoformat(),
        })

        disconnected = []
        for connection in self.session_connections[session_id]:
            try:
                await connection.send_text(message)
            except Exception:
                disconnected.append(connection)

        # Clean up disconnected clients
        for conn in disconnected:
            self.disconnect(conn, session_id)


# Global connection manager instance
manager = ConnectionManager()


@router.websocket("/ws")
async def websocket_endpoint(websocket: WebSocket):
    """Global WebSocket endpoint for all events."""
    await manager.connect(websocket)
    try:
        while True:
            # Keep connection alive and handle incoming messages
            data = await websocket.receive_text()
            try:
                message = json.loads(data)

                # Handle subscription requests
                if message.get("action") == "subscribe" and "session_id" in message:
                    session_id = message["session_id"]
                    if session_id not in manager.session_connections:
                        manager.session_connections[session_id] = []
                    manager.session_connections[session_id].append(websocket)
                    await websocket.send_text(json.dumps({
                        "event": "subscribed",
                        "session_id": session_id,
                    }))

                # Handle ping/pong
                elif message.get("action") == "ping":
                    await websocket.send_text(json.dumps({"event": "pong"}))

            except json.JSONDecodeError:
                pass  # Ignore invalid JSON

    except WebSocketDisconnect:
        manager.disconnect(websocket)


@router.websocket("/ws/{session_id}")
async def session_websocket_endpoint(websocket: WebSocket, session_id: str):
    """Session-specific WebSocket endpoint."""
    await manager.connect(websocket, session_id)
    try:
        while True:
            data = await websocket.receive_text()
            try:
                message = json.loads(data)

                # Handle ping/pong
                if message.get("action") == "ping":
                    await websocket.send_text(json.dumps({"event": "pong"}))

            except json.JSONDecodeError:
                pass

    except WebSocketDisconnect:
        manager.disconnect(websocket, session_id)


# =============================================================================
# Event Broadcasting Functions
# =============================================================================

async def emit_agent_status_changed(
    session_id: str,
    agent_id: str,
    status: str,
    iteration: int | None = None,
    cost: float | None = None,
):
    """Emit agent status change event."""
    data = {
        "agent_id": agent_id,
        "status": status,
    }
    if iteration is not None:
        data["iteration"] = iteration
    if cost is not None:
        data["cost"] = cost

    await manager.broadcast_to_session(session_id, "agent.status_changed", data)


async def emit_task_progress(
    session_id: str,
    task_id: str,
    status: str,
    progress: float | None = None,
):
    """Emit task progress event."""
    data = {
        "task_id": task_id,
        "status": status,
    }
    if progress is not None:
        data["progress"] = progress

    await manager.broadcast_to_session(session_id, "task.progress_updated", data)


async def emit_message_sent(
    session_id: str,
    from_agent: str,
    to_agent: str,
    message_type: str,
    subject: str | None = None,
):
    """Emit message sent event."""
    await manager.broadcast_to_session(session_id, "message.sent", {
        "from": from_agent,
        "to": to_agent,
        "type": message_type,
        "subject": subject,
    })


async def emit_pr_event(
    session_id: str,
    event_type: str,  # created, merged, failed
    pr_number: int,
    title: str | None = None,
):
    """Emit pull request event."""
    await manager.broadcast_to_session(session_id, f"pr.{event_type}", {
        "pr_number": pr_number,
        "title": title,
    })


async def emit_cost_updated(session_id: str, total_cost: float, agent_costs: dict[str, float]):
    """Emit cost update event."""
    await manager.broadcast_to_session(session_id, "cost.updated", {
        "total_cost": total_cost,
        "agent_costs": agent_costs,
    })


async def emit_log_entry(
    session_id: str,
    agent_id: str | None,
    level: str,
    message: str,
    data: dict[str, Any] | None = None,
):
    """Emit log entry event."""
    await manager.broadcast_to_session(session_id, "log.entry", {
        "agent_id": agent_id,
        "level": level,
        "message": message,
        "data": data,
        "timestamp": datetime.utcnow().isoformat(),
    })


async def emit_session_complete(session_id: str, status: str, summary: dict[str, Any]):
    """Emit session completion event."""
    await manager.broadcast_to_session(session_id, "session.complete", {
        "status": status,
        "summary": summary,
    })
