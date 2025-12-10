<script lang="ts">
	import '../app.css';
	import { isConnected } from '$lib/stores/dashboard';

	interface Props {
		children: import('svelte').Snippet;
	}

	let { children }: Props = $props();
</script>

<div class="app-layout">
	<header class="app-header">
		<div class="header-left">
			<span class="logo">🐝</span>
			<h1>Continuous Claude Dashboard</h1>
		</div>
		<div class="header-right">
			<span class="connection-status">
				<span class="status-dot {$isConnected ? 'running' : 'error'}"></span>
				{$isConnected ? 'Connected' : 'Disconnected'}
			</span>
		</div>
	</header>

	<main class="app-main">
		{@render children()}
	</main>

	<footer class="app-footer">
		<span>Continuous Claude v2.0</span>
		<span class="divider">|</span>
		<a href="https://github.com/anthropics/claude-code" target="_blank" rel="noopener">GitHub</a>
	</footer>
</div>

<style>
	.app-layout {
		display: flex;
		flex-direction: column;
		min-height: 100vh;
	}

	.app-header {
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: var(--spacing-md) var(--spacing-lg);
		background: var(--color-bg-secondary);
		border-bottom: 1px solid var(--color-border);
	}

	.header-left {
		display: flex;
		align-items: center;
		gap: var(--spacing-md);
	}

	.logo {
		font-size: 1.5rem;
	}

	.header-left h1 {
		font-size: 1.25rem;
		font-weight: 600;
	}

	.header-right {
		display: flex;
		align-items: center;
		gap: var(--spacing-md);
	}

	.connection-status {
		display: flex;
		align-items: center;
		gap: var(--spacing-xs);
		font-size: 0.875rem;
		color: var(--color-text-secondary);
	}

	.app-main {
		flex: 1;
		padding: var(--spacing-lg);
	}

	.app-footer {
		display: flex;
		align-items: center;
		justify-content: center;
		gap: var(--spacing-sm);
		padding: var(--spacing-md);
		background: var(--color-bg-secondary);
		border-top: 1px solid var(--color-border);
		font-size: 0.8125rem;
		color: var(--color-text-secondary);
	}

	.app-footer a {
		color: var(--color-info);
		text-decoration: none;
	}

	.app-footer a:hover {
		text-decoration: underline;
	}

	.divider {
		opacity: 0.5;
	}
</style>
