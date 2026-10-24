<script lang="ts">
  import Card from "$lib/ui/Card.svelte";
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import type { Status } from "$lib/state/machine.svelte";
  import { ago } from "$lib/pages/system/types";

  interface Props {
    status: Status | null;
    reindexing: boolean;
    message?: string;
    failed?: boolean;
    onreindex: () => void;
  }

  let { status, reindexing, message, failed = false, onreindex }: Props = $props();
</script>

<Card title="Vault index" gloss="書庫" lead="The machine map agents read before they touch this box.">
  {#snippet tools()}
    <Chip tone={status?.vault.exists ? "line" : "alert"}>{status?.vault.exists ? "Ready" : "Missing"}</Chip>
  {/snippet}
  <div class="vault-number"><strong>{status?.vault.files ?? "—"}</strong><span>indexed files</span></div>
  <dl>
    <div><dt>Last indexed</dt><dd>{status?.vault.lastIndexed ? ago(status.vault.lastIndexed) : "Never"}</dd></div>
    <div><dt>Location</dt><dd><code>{status?.vault.path || "Waiting for status"}</code></dd></div>
  </dl>
  <div class="actions">
    <Button variant="plate" icon="refresh" busy={reindexing} armed={!!status?.vault.exists} onclick={onreindex}>Reindex</Button>
    {#if message}<span class:failed>{message}</span>{/if}
  </div>
</Card>

<style>
  .vault-number { display: flex; align-items: baseline; gap: var(--s3); padding-bottom: var(--s4); border-bottom: 1px solid var(--line-soft); }
  .vault-number strong { color: var(--ink); font-family: var(--display); font-size: 42px; font-weight: 300; line-height: 1; }
  .vault-number span { color: var(--ink-mute); font-size: var(--f-small); }
  dl { margin: var(--s3) 0 0; }
  dl div { display: grid; grid-template-columns: 100px minmax(0, 1fr); gap: var(--s3); padding: var(--s2) 0; border-bottom: 1px solid var(--line-soft); }
  dt { color: var(--ink-mute); font-size: var(--f-small); }
  dd { margin: 0; min-width: 0; color: var(--ink); font-size: var(--f-small); text-align: right; }
  dd code { display: block; overflow: hidden; color: var(--ink-dim); font-size: var(--f-micro); text-overflow: ellipsis; white-space: nowrap; }
  .actions { display: flex; align-items: center; gap: var(--s3); margin-top: var(--s4); }
  .actions span { color: var(--ink-mute); font-size: var(--f-small); }
  .actions span.failed { color: var(--alert); }
</style>
