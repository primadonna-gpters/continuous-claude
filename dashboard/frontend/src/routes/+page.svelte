<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import AgentCard from '$lib/components/AgentCard.svelte';
	import LogStream from '$lib/components/LogStream.svelte';
	import {
		session,
		agents,
		tasks,
		metrics,
		logs,
		isLoading,
		error,
		loadDashboard,
		connectWebSocket,
		disconnectWebSocket,
		totalTasks
	} from '$lib/stores/dashboard';

	let sessionInput = $state('');

	onMount(() => {
		// Check for session ID in URL
		const urlParams = new URLSearchParams(window.location.search);
		const urlSessionId = urlParams.get('session');
		if (urlSessionId) {
			sessionInput = urlSessionId;
			handleLoadSession();
		}
	});

	onDestroy(() => {
		disconnectWebSocket();
	});

	function handleLoadSession() {
		if (sessionInput.trim()) {
			loadDashboard(sessionInput.trim());
			connectWebSocket(sessionInput.trim());
		}
	}

	function formatDuration(seconds: number): string {
		const mins = Math.floor(seconds / 60);
		const secs = Math.floor(seconds % 60);
		return `${mins}m ${secs}s`;
	}
</script>

<div class="dashboard">
	{#if !$session}
		<div class="session-input-container">
			<div class="card session-input-card">
				<h2>Enter Session ID</h2>
				<p>Enter a session ID to view the dashboard</p>
				<div class="input-group">
					<input
						type="text"
						bind:value={sessionInput}
						placeholder="e.g., 20251210-123456"
						onkeydown={(e) => e.key === 'Enter' && handleLoadSession()}
					/>
					<button onclick={handleLoadSession} disabled={$isLoading}>
						{$isLoading ? 'Loading...' : 'Load'}
					</button>
				</div>
				{#if $error}
					<p class="error">{$error}</p>
				{/if}
			</div>
		</div>
	{:else}
		<!-- Session Header -->
		<div class="session-header card">
			<div class="session-info">
				<div class="session-title">
					<h2>Session: {$session.id}</h2>
					<span class="badge badge-{$session.status === 'running' ? 'success' : $session.status === 'completed' ? 'info' : 'error'}">
						{$session.status}
					</span>
				</div>
				<p class="session-prompt">{$session.prompt}</p>
			</div>
			<div class="session-stats">
				<div class="stat-item">
					<span class="stat-value">{formatDuration($session.elapsed_time)}</span>
					<span class="stat-label">Duration</span>
				</div>
				<div class="stat-item">
					<span class="stat-value">${$metrics.total_cost.toFixed(2)}</span>
					<span class="stat-label">Total Cost</span>
				</div>
				<div class="stat-item">
					<span class="stat-value">{($metrics.success_rate * 100).toFixed(0)}%</span>
					<span class="stat-label">Success Rate</span>
				</div>
			</div>
		</div>

		<!-- Main Grid -->
		<div class="dashboard-grid">
			<!-- Agents Section -->
			<section class="agents-section">
				<h3>Agents ({$agents.length})</h3>
				<div class="agents-grid">
					{#each $agents as agent (agent.id)}
						<AgentCard {agent} />
					{:else}
						<p class="no-data">No agents registered</p>
					{/each}
				</div>
			</section>

			<!-- Task Queue Section -->
			<section class="tasks-section card">
				<h3>Task Queue ({$totalTasks})</h3>
				<div class="task-columns">
					<div class="task-column">
						<h4>⏳ Pending ({$tasks.pending.length})</h4>
						{#each $tasks.pending as task (task.id)}
							<div class="task-item pending">
								<span class="task-type">{task.type}</span>
								<span class="task-priority">P{task.priority}</span>
							</div>
						{:else}
							<span class="no-tasks">None</span>
						{/each}
					</div>
					<div class="task-column">
						<h4>🔄 In Progress ({$tasks.in_progress.length})</h4>
						{#each $tasks.in_progress as task (task.id)}
							<div class="task-item in-progress">
								<span class="task-type">{task.type}</span>
								<span class="task-agent">{task.agent_id}</span>
							</div>
						{:else}
							<span class="no-tasks">None</span>
						{/each}
					</div>
					<div class="task-column">
						<h4>✅ Completed ({$tasks.completed.length})</h4>
						{#each $tasks.completed.slice(0, 5) as task (task.id)}
							<div class="task-item completed">
								<span class="task-type">{task.type}</span>
							</div>
						{:else}
							<span class="no-tasks">None</span>
						{/each}
					</div>
					<div class="task-column">
						<h4>❌ Failed ({$tasks.failed.length})</h4>
						{#each $tasks.failed.slice(0, 5) as task (task.id)}
							<div class="task-item failed">
								<span class="task-type">{task.type}</span>
							</div>
						{:else}
							<span class="no-tasks">None</span>
						{/each}
					</div>
				</div>
			</section>

			<!-- Logs Section -->
			<section class="logs-section card">
				<h3>Live Logs</h3>
				<LogStream logs={$logs} maxHeight="300px" />
			</section>

			<!-- Metrics Section -->
			<section class="metrics-section card">
				<h3>Metrics</h3>
				<div class="metrics-grid">
					<div class="metric-card">
						<span class="metric-value">{$metrics.total_prs}</span>
						<span class="metric-label">Total PRs</span>
					</div>
					<div class="metric-card success">
						<span class="metric-value">{$metrics.merged_prs}</span>
						<span class="metric-label">Merged</span>
					</div>
					<div class="metric-card error">
						<span class="metric-value">{$metrics.failed_prs}</span>
						<span class="metric-label">Failed</span>
					</div>
					<div class="metric-card">
						<span class="metric-value">{$metrics.avg_iteration_time.toFixed(1)}s</span>
						<span class="metric-label">Avg Iteration</span>
					</div>
				</div>
			</section>
		</div>
	{/if}
</div>

<style>
	.dashboard {
		max-width: 1400px;
		margin: 0 auto;
	}

	.session-input-container {
		display: flex;
		justify-content: center;
		align-items: center;
		min-height: 60vh;
	}

	.session-input-card {
		max-width: 400px;
		text-align: center;
	}

	.session-input-card h2 {
		margin-bottom: var(--spacing-sm);
	}

	.session-input-card p {
		color: var(--color-text-secondary);
		margin-bottom: var(--spacing-lg);
	}

	.input-group {
		display: flex;
		gap: var(--spacing-sm);
	}

	.input-group input {
		flex: 1;
		padding: var(--spacing-sm) var(--spacing-md);
		background: var(--color-bg-tertiary);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		color: var(--color-text);
		font-size: 1rem;
	}

	.input-group button {
		padding: var(--spacing-sm) var(--spacing-lg);
		background: var(--color-info);
		border: none;
		border-radius: var(--radius-sm);
		color: white;
		font-weight: 600;
		cursor: pointer;
	}

	.input-group button:hover {
		opacity: 0.9;
	}

	.input-group button:disabled {
		opacity: 0.5;
		cursor: not-allowed;
	}

	.error {
		color: var(--color-error);
		margin-top: var(--spacing-md);
	}

	/* Session Header */
	.session-header {
		display: flex;
		justify-content: space-between;
		align-items: flex-start;
		margin-bottom: var(--spacing-lg);
	}

	.session-title {
		display: flex;
		align-items: center;
		gap: var(--spacing-md);
		margin-bottom: var(--spacing-sm);
	}

	.session-prompt {
		color: var(--color-text-secondary);
		font-size: 0.875rem;
		max-width: 600px;
	}

	.session-stats {
		display: flex;
		gap: var(--spacing-lg);
	}

	.stat-item {
		text-align: center;
	}

	.stat-item .stat-value {
		display: block;
		font-size: 1.5rem;
		font-weight: 700;
	}

	.stat-item .stat-label {
		font-size: 0.75rem;
		color: var(--color-text-secondary);
		text-transform: uppercase;
	}

	/* Dashboard Grid */
	.dashboard-grid {
		display: grid;
		grid-template-columns: 1fr 1fr;
		gap: var(--spacing-lg);
	}

	section h3 {
		margin-bottom: var(--spacing-md);
	}

	/* Agents */
	.agents-section {
		grid-column: 1 / -1;
	}

	.agents-grid {
		display: grid;
		grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
		gap: var(--spacing-md);
	}

	.no-data {
		color: var(--color-text-secondary);
		text-align: center;
		padding: var(--spacing-lg);
	}

	/* Tasks */
	.task-columns {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--spacing-md);
	}

	.task-column h4 {
		font-size: 0.875rem;
		margin-bottom: var(--spacing-sm);
	}

	.task-item {
		padding: var(--spacing-xs) var(--spacing-sm);
		border-radius: var(--radius-sm);
		font-size: 0.8125rem;
		margin-bottom: var(--spacing-xs);
		display: flex;
		justify-content: space-between;
	}

	.task-item.pending {
		background: rgba(107, 114, 128, 0.2);
	}
	.task-item.in-progress {
		background: rgba(59, 130, 246, 0.2);
	}
	.task-item.completed {
		background: rgba(34, 197, 94, 0.2);
	}
	.task-item.failed {
		background: rgba(239, 68, 68, 0.2);
	}

	.task-type {
		font-family: var(--font-mono);
	}

	.task-priority,
	.task-agent {
		color: var(--color-text-secondary);
		font-size: 0.75rem;
	}

	.no-tasks {
		color: var(--color-text-secondary);
		font-size: 0.8125rem;
	}

	/* Metrics */
	.metrics-grid {
		display: grid;
		grid-template-columns: repeat(4, 1fr);
		gap: var(--spacing-md);
	}

	.metric-card {
		text-align: center;
		padding: var(--spacing-md);
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
	}

	.metric-card .metric-value {
		display: block;
		font-size: 1.5rem;
		font-weight: 700;
	}

	.metric-card .metric-label {
		font-size: 0.75rem;
		color: var(--color-text-secondary);
		text-transform: uppercase;
	}

	.metric-card.success .metric-value {
		color: var(--color-success);
	}
	.metric-card.error .metric-value {
		color: var(--color-error);
	}

	/* Responsive */
	@media (max-width: 1024px) {
		.dashboard-grid {
			grid-template-columns: 1fr;
		}

		.task-columns {
			grid-template-columns: repeat(2, 1fr);
		}

		.metrics-grid {
			grid-template-columns: repeat(2, 1fr);
		}
	}
</style>
