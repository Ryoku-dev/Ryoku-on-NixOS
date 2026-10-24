<!-- An empty screen is an invitation to act: what is missing, and the one
     thing that fills it. -->
<script lang="ts">
  import type { Snippet } from "svelte";
  import Icon from "./Icon.svelte";
  import type { IconName } from "./icons";

  interface Props {
    icon?: IconName;
    title: string;
    body?: string;
    action?: Snippet;
  }

  let { icon = "spark", title, body, action }: Props = $props();
</script>

<div class="empty">
  <span class="empty-glyph"><Icon name={icon} size={22} weight={1.25} /></span>
  <p class="empty-title">{title}</p>
  {#if body}<p class="empty-body">{body}</p>{/if}
  {#if action}<div class="empty-action">{@render action()}</div>{/if}
</div>

<style>
  .empty {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: var(--s2);
    padding: var(--s6) var(--s5);
    border: 1px dashed var(--line-soft);
    border-radius: var(--radius);
    max-width: 48ch;
  }
  .empty-glyph { color: var(--ink-faint); margin-bottom: var(--s1); }
  .empty-title { font-size: var(--f-row); color: var(--ink); }
  .empty-body { color: var(--ink-mute); font-size: var(--f-small); }
  .empty-action { margin-top: var(--s2); }
</style>
