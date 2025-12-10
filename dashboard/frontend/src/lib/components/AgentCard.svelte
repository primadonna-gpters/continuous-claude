<script lang="ts">
	import type { AgentStatus } from '$lib/stores/dashboard';

	interface Props {
		agent: AgentStatus;
	}

	let { agent }: Props = $props();

	const personaEmoji: Record<string, string> = {
		developer: '🧑‍💻',
		tester: '🧪',
		reviewer: '👁️',
		documenter: '📚',
		security: '🔒'
	};

	const statusColor: Record<string, string> = {
		running: 'var(--color-running)',
		waiting: 'var(--color-warning)',
		idle: 'var(--color-idle)',
		error: 'var(--color-error)'
	};
</script>

<div class="agent-card">
	<div class="agent-header">
		<span class="agent-emoji">{personaEmoji[agent.persona] ?? '🤖'}</span>
		<div class="agent-info">
			<span class="agent-name">{agent.id}</span>
			<span class="agent-persona">{agent.persona}</span>
		</div>
		<span class="status-dot {agent.status}"></span>
	</div>

	<div class="agent-stats">
		<div class="stat">
			<span class="stat-label">Status</span>
			<span class="stat-value" style="color: {statusColor[agent.status]}">{agent.status}</span>
		</div>
		<div class="stat">
			<span class="stat-label">Iteration</span>
			<span class="stat-value">{agent.iteration}</span>
		</div>
		<div class="stat">
			<span class="stat-label">Cost</span>
			<span class="stat-value">${agent.cost.toFixed(2)}</span>
		</div>
	</div>

	{#if agent.current_task}
		<div class="current-task">
			<span class="task-label">Current Task:</span>
			<span class="task-value">{agent.current_task}</span>
		</div>
	{/if}
</div>

<style>
	.agent-card {
		background: var(--color-bg-secondary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: var(--spacing-md);
	}

	.agent-header {
		display: flex;
		align-items: center;
		gap: var(--spacing-sm);
		margin-bottom: var(--spacing-md);
	}

	.agent-emoji {
		font-size: 1.5rem;
	}

	.agent-info {
		flex: 1;
		display: flex;
		flex-direction: column;
	}

	.agent-name {
		font-weight: 600;
		font-size: 0.9375rem;
	}

	.agent-persona {
		color: var(--color-text-secondary);
		font-size: 0.75rem;
		text-transform: capitalize;
	}

	.agent-stats {
		display: grid;
		grid-template-columns: repeat(3, 1fr);
		gap: var(--spacing-sm);
	}

	.stat {
		display: flex;
		flex-direction: column;
		text-align: center;
		padding: var(--spacing-xs);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
	}

	.stat-label {
		font-size: 0.6875rem;
		color: var(--color-text-secondary);
		text-transform: uppercase;
	}

	.stat-value {
		font-weight: 600;
		font-size: 0.875rem;
	}

	.current-task {
		margin-top: var(--spacing-md);
		padding: var(--spacing-sm);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-sm);
		font-size: 0.8125rem;
	}

	.task-label {
		color: var(--color-text-secondary);
		margin-right: var(--spacing-xs);
	}

	.task-value {
		font-family: var(--font-mono);
	}
</style>
