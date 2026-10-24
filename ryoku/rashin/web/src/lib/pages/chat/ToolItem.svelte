<script lang="ts">
  import type { Permission, ToolItem as ToolItemState } from "$chatstate";
  import Diff from "$lib/content/Diff.svelte";
  import ThinkingOrb from "$lib/fx/ThinkingOrb.svelte";
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Fold from "$lib/ui/Fold.svelte";
  import Icon from "$lib/ui/Icon.svelte";
  import PermissionRequest from "./PermissionRequest.svelte";
  import { toolIcon } from "./presentation";

  interface Props {
    item: ToolItemState;
    permissions: Permission[];
    onanswer: (requestId: string, optionId: string) => void;
  }

  let { item, permissions, onanswer }: Props = $props();
  let open = $state(false);
  let expandedOutput = $state(false);
  let previousStatus = $state("");
  const live = $derived(item.status === "pending" || item.status === "in_progress");
  const longOutput = $derived(item.output.length > 900 || item.output.split("\n").length > 12);

  $effect(() => {
    if (!previousStatus) open = item.status === "pending" || item.status === "in_progress" || item.status === "failed";
    else if (item.status === "failed" && previousStatus !== "failed") open = true;
    previousStatus = item.status;
  });
</script>

<article class="tool-item">
  <Fold bind:open class="tool-fold">
    {#snippet summary()}
      <span class="tool-summary">
        <span class="tool-glyph"><Icon name={toolIcon(item.kind2)} size={15} /></span>
        <span class="tool-title">{item.title || item.kind2 || "Tool"}</span>
        <span class="tool-meta">
          {#if item.auto}<Chip tone="quiet">auto</Chip>{/if}
          <Chip tone={item.status === "failed" ? "alert" : live ? "line" : "quiet"}>
            {#if live}<ThinkingOrb mode="working" size={20} label={item.status === "pending" ? "Pending" : "Working"} />{/if}
            {item.status.replaceAll("_", " ")}
          </Chip>
        </span>
      </span>
    {/snippet}

    <div class="tool-details">
      {#if item.input}
        <section>
          <span class="detail-label">Input</span>
          <pre>{item.input}</pre>
        </section>
      {/if}
      {#if item.output}
        <section>
          <span class="detail-label">Output</span>
          <pre class="output" class:expanded={expandedOutput}>{item.output}</pre>
          {#if longOutput}
            <Button variant="quiet" size="sm" onclick={() => expandedOutput = !expandedOutput}>
              {expandedOutput ? "Show less" : "Show more"}
            </Button>
          {/if}
        </section>
      {/if}
      {#if item.diffs.length}<Diff diffs={item.diffs} />{/if}
      {#if !item.input && !item.output && !item.diffs.length}
        <p class="no-details">No details were reported for this tool.</p>
      {/if}
    </div>
  </Fold>

  {#each permissions as permission (permission.requestId)}
    <PermissionRequest {permission} {onanswer} />
  {/each}
</article>

<style>
  .tool-item { margin-left: 40px; animation: item-in var(--t-mid) var(--ease-out); }
  :global(.tool-fold) { padding: var(--s2) var(--s3); border: 1px solid var(--line-soft); border-radius: var(--radius); background: var(--tint5); }
  .tool-summary { display: flex; align-items: center; gap: var(--s2); min-width: 0; }
  .tool-glyph { display: inline-flex; flex: none; color: var(--ink-mute); }
  .tool-title { overflow: hidden; min-width: 0; flex: 1; color: var(--ink-dim); font-size: var(--f-small); text-overflow: ellipsis; white-space: nowrap; }
  .tool-meta { display: inline-flex; align-items: center; gap: var(--s1); flex: none; }
  .tool-details { display: flex; flex-direction: column; gap: var(--s3); padding: var(--s3) 0 var(--s1) 22px; }
  .tool-details section { min-width: 0; }
  .detail-label { display: block; margin-bottom: var(--s1); color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); letter-spacing: var(--track-label); text-transform: uppercase; }
  pre {
    overflow: auto;
    padding: var(--s2) var(--s3);
    border: 1px solid var(--line-soft);
    border-radius: 4px;
    background: var(--paper);
    color: var(--ink-dim);
    font-size: var(--f-small);
    line-height: 1.55;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  pre.output { max-height: 224px; }
  pre.output.expanded { max-height: none; }
  .no-details { color: var(--ink-mute); font-size: var(--f-small); }
  @keyframes item-in { from { opacity: 0; transform: translateY(4px); } }
  @media (max-width: 760px) { .tool-item { margin-left: 0; } }
</style>
