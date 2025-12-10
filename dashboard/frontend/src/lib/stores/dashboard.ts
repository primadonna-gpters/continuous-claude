/**
 * Dashboard state management using Svelte 5 runes
 */
import { writable, derived, type Writable } from 'svelte/store';

// =============================================================================
// Types
// =============================================================================

export interface SessionInfo {
	id: string;
	started_at: string;
	prompt: string;
	total_cost: number;
	status: string;
	elapsed_time: number;
}

export interface AgentStatus {
	id: string;
	persona: string;
	status: 'idle' | 'running' | 'waiting' | 'error';
	current_task: string | null;
	iteration: number;
	cost: number;
	worktree: string | null;
	last_activity: string | null;
}

export interface TaskInfo {
	id: string;
	type: string;
	status: 'pending' | 'in_progress' | 'completed' | 'failed';
	priority: number;
	agent_id: string | null;
	payload: Record<string, unknown> | null;
	created_at: string;
}

export interface TaskQueue {
	pending: TaskInfo[];
	in_progress: TaskInfo[];
	completed: TaskInfo[];
	failed: TaskInfo[];
}

export interface Message {
	id: string;
	from_agent: string;
	to_agent: string;
	type: string;
	subject: string | null;
	body: Record<string, unknown> | null;
	read: boolean;
	created_at: string;
}

export interface LogEntry {
	id: number;
	session_id: string;
	agent_id: string | null;
	level: 'info' | 'warning' | 'error' | 'debug';
	message: string;
	data: Record<string, unknown> | null;
	created_at: string;
}

export interface Metrics {
	success_rate: number;
	avg_iteration_time: number;
	total_prs: number;
	merged_prs: number;
	failed_prs: number;
	total_cost: number;
}

export interface DashboardState {
	session: SessionInfo | null;
	agents: AgentStatus[];
	tasks: TaskQueue;
	recent_messages: Message[];
	pending_messages: number;
	metrics: Metrics;
	recent_logs: LogEntry[];
}

// =============================================================================
// Stores
// =============================================================================

export const sessionId = writable<string | null>(null);
export const isConnected = writable(false);
export const isLoading = writable(false);
export const error = writable<string | null>(null);

export const session = writable<SessionInfo | null>(null);
export const agents = writable<AgentStatus[]>([]);
export const tasks = writable<TaskQueue>({
	pending: [],
	in_progress: [],
	completed: [],
	failed: []
});
export const messages = writable<Message[]>([]);
export const pendingMessages = writable(0);
export const metrics = writable<Metrics>({
	success_rate: 0,
	avg_iteration_time: 0,
	total_prs: 0,
	merged_prs: 0,
	failed_prs: 0,
	total_cost: 0
});
export const logs = writable<LogEntry[]>([]);

// =============================================================================
// Derived Stores
// =============================================================================

export const totalTasks = derived(tasks, ($tasks) => {
	return (
		$tasks.pending.length +
		$tasks.in_progress.length +
		$tasks.completed.length +
		$tasks.failed.length
	);
});

export const activeAgents = derived(agents, ($agents) => {
	return $agents.filter((a) => a.status === 'running' || a.status === 'waiting');
});

export const totalCost = derived(agents, ($agents) => {
	return $agents.reduce((sum, agent) => sum + agent.cost, 0);
});

// =============================================================================
// Actions
// =============================================================================

export async function loadDashboard(id: string): Promise<void> {
	isLoading.set(true);
	error.set(null);
	sessionId.set(id);

	try {
		const response = await fetch(`/api/dashboard/${id}`);
		if (!response.ok) {
			throw new Error(`Failed to load dashboard: ${response.statusText}`);
		}

		const data: DashboardState = await response.json();

		session.set(data.session);
		agents.set(data.agents);
		tasks.set(data.tasks);
		messages.set(data.recent_messages);
		pendingMessages.set(data.pending_messages);
		metrics.set(data.metrics);
		logs.set(data.recent_logs);
	} catch (err) {
		error.set(err instanceof Error ? err.message : 'Unknown error');
	} finally {
		isLoading.set(false);
	}
}

export function addLogEntry(entry: LogEntry): void {
	logs.update((current) => [entry, ...current.slice(0, 99)]);
}

export function updateAgentStatus(agentId: string, update: Partial<AgentStatus>): void {
	agents.update((current) =>
		current.map((agent) => (agent.id === agentId ? { ...agent, ...update } : agent))
	);
}

export function updateTaskStatus(taskId: string, status: TaskInfo['status']): void {
	tasks.update((current) => {
		// Find and remove task from current status
		let task: TaskInfo | undefined;
		for (const key of ['pending', 'in_progress', 'completed', 'failed'] as const) {
			const index = current[key].findIndex((t) => t.id === taskId);
			if (index !== -1) {
				task = current[key][index];
				current[key] = current[key].filter((_, i) => i !== index);
				break;
			}
		}

		// Add to new status
		if (task) {
			task.status = status;
			current[status === 'in_progress' ? 'in_progress' : status].push(task);
		}

		return { ...current };
	});
}

// =============================================================================
// WebSocket Connection
// =============================================================================

let ws: WebSocket | null = null;

export function connectWebSocket(id: string): void {
	if (ws) {
		ws.close();
	}

	const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
	const wsUrl = `${protocol}//${window.location.host}/ws/${id}`;

	ws = new WebSocket(wsUrl);

	ws.onopen = () => {
		isConnected.set(true);
		console.log('WebSocket connected');
	};

	ws.onclose = () => {
		isConnected.set(false);
		console.log('WebSocket disconnected');

		// Reconnect after 3 seconds
		setTimeout(() => {
			const currentId = sessionId;
			if (currentId) {
				connectWebSocket(id);
			}
		}, 3000);
	};

	ws.onerror = (event) => {
		console.error('WebSocket error:', event);
		error.set('WebSocket connection error');
	};

	ws.onmessage = (event) => {
		try {
			const data = JSON.parse(event.data);
			handleWebSocketEvent(data);
		} catch (err) {
			console.error('Failed to parse WebSocket message:', err);
		}
	};
}

export function disconnectWebSocket(): void {
	if (ws) {
		ws.close();
		ws = null;
	}
	isConnected.set(false);
}

function handleWebSocketEvent(event: { event: string; data: Record<string, unknown> }): void {
	switch (event.event) {
		case 'agent.status_changed':
			updateAgentStatus(event.data.agent_id as string, event.data as Partial<AgentStatus>);
			break;

		case 'task.progress_updated':
			updateTaskStatus(event.data.task_id as string, event.data.status as TaskInfo['status']);
			break;

		case 'log.entry':
			addLogEntry(event.data as unknown as LogEntry);
			break;

		case 'cost.updated':
			metrics.update((m) => ({ ...m, total_cost: event.data.total_cost as number }));
			break;

		case 'message.sent':
			pendingMessages.update((n) => n + 1);
			break;

		case 'session.complete':
			session.update((s) => (s ? { ...s, status: event.data.status as string } : s));
			break;

		default:
			console.log('Unknown WebSocket event:', event.event);
	}
}
