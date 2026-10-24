<script lang="ts">
  import type { Snippet } from "svelte";
  import { Popover } from "bits-ui";

  interface Props {
    open?: boolean;
    side?: "top" | "bottom" | "left" | "right";
    align?: "start" | "center" | "end";
    width?: number;
    /** false keeps focus where it was (a typeahead that rides a text field) */
    focusContent?: boolean;
    trigger: Snippet<[{ props: Record<string, unknown> }]>;
    children: Snippet;
  }

  let { open = $bindable(false), side = "bottom", align = "end", width, focusContent = true, trigger, children }: Props = $props();
</script>

<Popover.Root bind:open>
  <Popover.Trigger>
    {#snippet child({ props })}
      {@render trigger({ props })}
    {/snippet}
  </Popover.Trigger>
  <Popover.Portal>
    <Popover.Content
      class="pop"
      {side}
      {align}
      sideOffset={6}
      style={width ? `width:${width}px` : ""}
      trapFocus={focusContent}
      onOpenAutoFocus={(e) => {
        if (!focusContent) e.preventDefault();
      }}
      onCloseAutoFocus={(e) => {
        if (!focusContent) e.preventDefault();
      }}
    >
      {@render children()}
    </Popover.Content>
  </Popover.Portal>
</Popover.Root>

<style>
  :global(.pop) {
    z-index: 50;
    padding: var(--s2);
    border: 1px solid var(--line-strong);
    border-radius: var(--radius);
    background: var(--paper-lift);
    animation: pop-in var(--t-fast) var(--ease-out);
    transform-origin: var(--bits-popover-content-transform-origin, top);
  }
  @keyframes pop-in { from { opacity: 0; transform: scale(0.97); } to { opacity: 1; transform: none; } }
</style>
