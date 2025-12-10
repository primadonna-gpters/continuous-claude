<script lang="ts">
	import type { LogEntry } from '$lib/stores/dashboard';

	interface Props {
		logs: LogEntry[];
		maxHeight?: string;
	}

	let { logs, maxHeight = '400px' }: Props = $props();

	function formatTime(timestamp: string): string {
		const date = new Date(timestamp);
		return date.toLocaleTimeString('en-US', {
			hour12: false,
			hour: '2-digit',
			minute: '2-digit',
			second: '2-digit'
		});
	}

	const levelIcon: Record<string, string> = {
		info: 'ℹ️',
		warning: '⚠️',
		error: '❌',
		debug: '🔍'
	};
</script>

<div class="log-stream" style="max-height: {maxHeight}">
	{#each logs as log (log.id)}
		<div class="log-entry {log.level}">
			<span class="log-icon">{levelIcon[log.level] ?? '📝'}</span>
			<span class="log-timestamp">{formatTime(log.created_at)}</span>
			{#if log.agent_id}
				<span class="log-agent">[{log.agent_id}]</span>
			{/if}
			<span class="log-message">{log.message}</span>
		</div>
	{:else}
		<div class="no-logs">No log entries</div>
	{/each}
</div>

<style>
	.log-stream {
		overflow-y: auto;
		background: var(--color-bg-tertiary);
		border-radius: var(--radius-md);
		padding: var(--spacing-sm);
	}

	.log-entry {
		display: flex;
		align-items: flex-start;
		gap: var(--spacing-sm);
		padding: var(--spacing-xs) var(--spacing-sm);
		border-radius: var(--radius-sm);
		font-family: var(--font-mono);
		font-size: 0.8125rem;
		margin-bottom: 2px;
	}

	.log-entry.info {
		background: rgba(59, 130, 246, 0.1);
	}
	.log-entry.warning {
		background: rgba(245, 158, 11, 0.1);
	}
	.log-entry.error {
		background: rgba(239, 68, 68, 0.1);
	}
	.log-entry.debug {
		background: rgba(107, 114, 128, 0.1);
	}

	.log-icon {
		flex-shrink: 0;
	}

	.log-timestamp {
		color: var(--color-text-secondary);
		flex-shrink: 0;
	}

	.log-agent {
		color: var(--color-info);
		flex-shrink: 0;
	}

	.log-message {
		word-break: break-word;
	}

	.no-logs {
		text-align: center;
		color: var(--color-text-secondary);
		padding: var(--spacing-lg);
	}
</style>
