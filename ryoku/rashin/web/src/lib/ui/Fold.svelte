<!-- Disclosure, not a wall: a folded block says what it hides and opens with
     a height that follows its content. -->
<script lang="ts">
  import type { Snippet } from "svelte";
  import { Collapsible } from "bits-ui";
  import Icon from "./Icon.svelte";
  import type { IconName } from "./icons";

  interface Props {
    open?: boolean;
    icon?: IconName;
    summary: Snippet;
    children: Snippet;
    class?: string;
  }

  let { open = $bindable(false), icon, summary, children, class: cls = "" }: Props = $props();
</script>

<Collapsible.Root bind:open class="fold {cls}">
  <Collapsible.Trigger class="fold-head">
    <span class="fold-chev" class:open><Icon name="chevronRight" size={14} /></span>
    {#if icon}<Icon name={icon} size={14} />{/if}
    <span class="fold-summary">{@render summary()}</span>
  </Collapsible.Trigger>
  <Collapsible.Content forceMount>
    {#snippet child({ props })}
      {@const { class: _ignored, ...rest } = props as Record<string, unknown> & { class?: string }}
      <div class="fold-wrap" {...rest}>
        <div class="fold-inner">{@render children()}</div>
      </div>
    {/snippet}
  </Collapsible.Content>
</Collapsible.Root>

<style>
  :global(.fold) { display: block; }
  :global(.fold-head) {
    display: flex;
    align-items: center;
    gap: var(--s2);
    width: 100%;
    padding: var(--s1) 0;
    color: var(--ink-mute);
    font-size: var(--f-small);
    text-align: left;
    transition: color var(--t-fast) var(--ease);
  }
  :global(.fold-head:hover) { color: var(--ink-dim); }
  .fold-chev { display: inline-flex; transition: transform var(--t-mid) var(--ease-out); }
  .fold-chev.open { transform: rotate(90deg); }
  .fold-summary { flex: 1; min-width: 0; }
  .fold-wrap {
    display: grid;
    grid-template-rows: 0fr;
    opacity: 0;
    transition: grid-template-rows var(--t-mid) var(--ease-out), opacity var(--t-mid) var(--ease);
  }
  .fold-wrap[data-state="open"] { grid-template-rows: 1fr; opacity: 1; }
  .fold-inner { overflow: hidden; min-height: 0; }
</style>
