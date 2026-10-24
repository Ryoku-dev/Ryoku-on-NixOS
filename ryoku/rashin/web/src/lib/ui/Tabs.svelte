<!-- Sheet tabs: a hairline row of names, the active one underlined in bone. -->
<script lang="ts">
  import type { Snippet } from "svelte";
  import { Tabs } from "bits-ui";

  interface Tab {
    value: string;
    label: string;
    count?: number;
  }

  interface Props {
    tabs: Tab[];
    value: string;
    onchange?: (value: string) => void;
    children: Snippet<[string]>;
  }

  let { tabs, value = $bindable(), onchange, children }: Props = $props();
</script>

<Tabs.Root bind:value onValueChange={(v) => onchange?.(v)} class="tabs">
  <Tabs.List class="tabs-list">
    {#each tabs as t (t.value)}
      <Tabs.Trigger value={t.value} class="tab">
        {t.label}{#if t.count !== undefined}<span class="tab-count">{t.count}</span>{/if}
      </Tabs.Trigger>
    {/each}
  </Tabs.List>
  {#each tabs as t (t.value)}
    <Tabs.Content value={t.value} class="tab-pane">{@render children(t.value)}</Tabs.Content>
  {/each}
</Tabs.Root>

<style>
  :global(.tabs) { display: flex; flex-direction: column; min-height: 0; }
  :global(.tabs-list) {
    display: flex;
    gap: var(--s4);
    border-bottom: 1px solid var(--line-soft);
    margin-bottom: var(--s5);
    overflow-x: auto;
  }
  :global(.tab) {
    position: relative;
    display: inline-flex;
    align-items: center;
    gap: var(--s2);
    padding: var(--s2) 0 var(--s3);
    color: var(--ink-mute);
    font-size: var(--f-row);
    white-space: nowrap;
    transition: color var(--t-fast) var(--ease);
  }
  :global(.tab::after) {
    content: "";
    position: absolute;
    left: 0; right: 0; bottom: -1px;
    height: 1px;
    background: var(--bone);
    transform: scaleX(0);
    transform-origin: left;
    transition: transform var(--t-mid) var(--ease-out);
  }
  :global(.tab:hover) { color: var(--ink-dim); }
  :global(.tab[data-state="active"]) { color: var(--ink); }
  :global(.tab[data-state="active"]::after) { transform: scaleX(1); }
  .tab-count { font-family: var(--mono); font-size: var(--f-micro); color: var(--ink-faint); }
  :global(.tab-pane) { min-height: 0; }
  :global(.tab-pane[data-state="active"]) { animation: pane-in var(--t-mid) var(--ease-out); }
  @keyframes pane-in { from { opacity: 0; transform: translateY(4px); } }
</style>
