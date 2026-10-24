<script lang="ts">
  import Empty from "$lib/ui/Empty.svelte";
  import Button from "$lib/ui/Button.svelte";
  import type { AskAction } from "./askstream";
  import Fold from "$lib/ui/Fold.svelte";

  export interface RecentAsk {
    id: string;
    at: string;
    kind?: string;
    q: string;
    a: string;
    images?: string[];
    actions?: AskAction[];
    via?: string;
    needsAgent?: boolean;
    needsAgentReason?: string;
  }

  interface Props {
    asks: RecentAsk[];
    error?: string;
    onselect?: (ask: RecentAsk) => void;
    oncontinue: (ask: RecentAsk) => void;
  }

  let { asks, error = "", onselect, oncontinue }: Props = $props();

  function ago(value: string): string {
    const elapsed = (Date.now() - new Date(value).getTime()) / 1000;
    if (!Number.isFinite(elapsed) || elapsed < 0) return "recently";
    if (elapsed < 90) return "moments ago";
    if (elapsed < 3600) return `${Math.round(elapsed / 60)} min ago`;
    if (elapsed < 86400) return `${Math.round(elapsed / 3600)} h ago`;
    return `${Math.round(elapsed / 86400)} d ago`;
  }
</script>

<section class="recent" aria-label="Recent asks">
  <Fold>
    {#snippet summary()}
      <span class="fold-title">Recent asks <span>{asks.length}</span></span>
    {/snippet}
    <div class="recent-body">
      {#if error}
        <Empty title="Recent asks are unavailable" body="Start the Rashin daemon, then return here to load the shared history." />
      {:else if asks.length === 0}
        <Empty title="No recent asks" body="Finished Ask answers will appear here." />
      {:else}
        <div class="plates">
          {#each asks as ask (ask.id || ask.at + ask.q)}
            <div class="plate">
              <button class="question" type="button" onclick={() => onselect?.(ask)}>
                <span>{ask.q}</span>
                <time datetime={ask.at}>{ago(ask.at)}</time>
              </button>
              {#if ask.via}<span class="via">{ask.via}</span>{/if}
              <Button size="sm" variant={ask.needsAgent ? "plate" : "quiet"} onclick={() => oncontinue(ask)}>
                {ask.needsAgent ? "Move to Agent" : "Continue"}
              </Button>
            </div>
          {/each}
        </div>
      {/if}
    </div>
  </Fold>
</section>

<style>
  .recent { min-width: 0; padding-top: var(--s3); border-top: 1px solid var(--line-soft); }
  .fold-title { display: flex; justify-content: space-between; width: 100%; }
  .fold-title span { color: var(--ink-faint); font-family: var(--mono); }
  .recent-body { padding-top: var(--s2); }
  .plate { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: var(--s2); }
  .question { display: flex; min-width: 0; align-items: center; gap: var(--s3); text-align: left; }
  .question > span { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .via { grid-column: 1; overflow: hidden; color: var(--ink-faint); font-size: var(--f-micro); text-overflow: ellipsis; white-space: nowrap; }
  time { flex: none; font-family: var(--mono); font-size: var(--f-tiny); letter-spacing: var(--track-label); text-transform: uppercase; color: var(--ink-faint); }
</style>
