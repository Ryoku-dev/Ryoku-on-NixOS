<script lang="ts">
  import type { Snippet } from "svelte";
  import { Tooltip } from "bits-ui";

  interface Props {
    text: string;
    side?: "top" | "bottom" | "left" | "right";
    children: Snippet;
  }

  let { text, side = "bottom", children }: Props = $props();
</script>

<Tooltip.Root delayDuration={350}>
  <Tooltip.Trigger>
    {#snippet child({ props })}
      <span class="trigger" {...props}>{@render children()}</span>
    {/snippet}
  </Tooltip.Trigger>
  <Tooltip.Portal>
    <Tooltip.Content {side} sideOffset={6}>
      {#snippet child({ props, open })}
        {#if open}
          <div class="tip" {...props}>{text}</div>
        {/if}
      {/snippet}
    </Tooltip.Content>
  </Tooltip.Portal>
</Tooltip.Root>

<style>
  .trigger { display: inline-flex; }
  .tip {
    z-index: 60;
    padding: var(--s1) var(--s2);
    border-radius: var(--radius);
    background: var(--bone);
    color: var(--ink-on-bone);
    font-size: var(--f-small);
    line-height: 1.3;
    white-space: nowrap;
    animation: tip-in var(--t-fast) var(--ease-out);
  }
  @keyframes tip-in { from { opacity: 0; transform: translateY(2px); } to { opacity: 1; transform: none; } }
</style>
