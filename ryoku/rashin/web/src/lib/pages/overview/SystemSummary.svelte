<script lang="ts">
  import Card from "$lib/ui/Card.svelte";
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import type { SystemInventory } from "$lib/pages/system/types";

  interface Props {
    inventory: SystemInventory | null;
    loading: boolean;
    error?: string;
    onopen: () => void;
    onrefresh: () => void;
  }

  let { inventory, loading, error, onopen, onrefresh }: Props = $props();
  const act = $derived(inventory?.tips.filter((tip) => tip.severity === "act").length ?? 0);
</script>

<Card title="System" gloss="演算" lead="The services, schedules and exposed edges on this machine.">
  {#snippet tools()}
    {#if inventory}<Chip tone={act ? "alert" : "line"}>{act ? `${act} need action` : "No urgent tips"}</Chip>{/if}
  {/snippet}
  {#if error}
    <div class="system-error"><p>{error} Rescan to try the daemon again.</p><Button size="sm" icon="refresh" busy={loading} onclick={onrefresh}>Rescan</Button></div>
  {:else if inventory}
    <dl>
      <div><dt>Services running</dt><dd>{inventory.services.runningN}/{inventory.services.totalN}</dd></div>
      <div><dt>Timers</dt><dd>{inventory.timers.active.length}{#if inventory.timers.passive.length}<small> · {inventory.timers.passive.length} dormant</small>{/if}</dd></div>
      <div><dt>Containers up</dt><dd>{inventory.containers.runningN}/{inventory.containers.totalN}</dd></div>
      <div><dt>Listening sockets</dt><dd>{inventory.listeners.rows.length}</dd></div>
      <div><dt>Things to look at</dt><dd class:attention={act > 0}>{act ? `${act} act · ${inventory.tips.length}` : inventory.tips.length}</dd></div>
    </dl>
    <Button variant="line" icon="arrowRight" onclick={onopen}>Open system inventory</Button>
  {:else}
    <p class="loading">{loading ? "Reading the machine…" : "No machine inventory yet."}</p>
  {/if}
</Card>

<style>
  dl { margin: 0 0 var(--s4); }
  dl div { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s4); padding: var(--s2) 0; border-bottom: 1px solid var(--line-soft); }
  dt { color: var(--ink-mute); font-size: var(--f-small); }
  dd { margin: 0; color: var(--ink); font-size: var(--f-row); font-weight: 500; font-variant-numeric: tabular-nums; }
  dd small { color: var(--ink-faint); font-size: var(--f-micro); font-weight: 400; }
  dd.attention { color: var(--alert); }
  .loading, .system-error p { color: var(--ink-mute); font-size: var(--f-small); }
  .system-error { display: flex; flex-direction: column; align-items: flex-start; gap: var(--s3); }
</style>
