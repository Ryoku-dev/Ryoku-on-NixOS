<script lang="ts">
  import type { HandoffItem } from "$chatstate";

  interface Props {
    item: HandoffItem;
  }

  let { item }: Props = $props();
</script>

<article class="handoff-card" aria-label="Context handed off from Ask">
  <header>
    <span class="t-label">From Ask</span>
    {#if item.askId}<code>{item.askId}</code>{/if}
  </header>
  <strong>{item.question}</strong>
  {#if item.answer}<p>{item.answer}</p>{/if}
</article>

<style>
  .handoff-card { width: min(100%, 680px); padding: var(--s3) var(--s4); border: 1px solid var(--line); border-left-color: var(--bone); border-radius: var(--radius); background: var(--tint5); animation: item-in var(--t-mid) var(--ease-out); }
  header { display: flex; align-items: center; justify-content: space-between; gap: var(--s3); margin-bottom: var(--s2); }
  code { overflow: hidden; color: var(--ink-faint); font-size: var(--f-tiny); text-overflow: ellipsis; white-space: nowrap; }
  strong { display: block; color: var(--ink); font-size: var(--f-small); font-weight: 500; line-height: 1.45; }
  p { display: -webkit-box; margin-top: var(--s2); overflow: hidden; color: var(--ink-mute); font-size: var(--f-small); line-height: 1.45; -webkit-box-orient: vertical; line-clamp: 3; -webkit-line-clamp: 3; }
  @keyframes item-in { from { opacity: 0; transform: translateY(4px); } }
</style>
