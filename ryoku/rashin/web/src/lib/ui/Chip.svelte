<!-- A small hairline tag. `tone="alert"` is the one red: data that is an alert. -->
<script lang="ts">
  import type { Snippet } from "svelte";

  interface Props {
    tone?: "line" | "plate" | "alert" | "quiet";
    mono?: boolean;
    children: Snippet;
  }

  let { tone = "line", mono = false, children }: Props = $props();
</script>

<span class="chip {tone}" class:mono>{@render children()}</span>

<style>
  .chip {
    display: inline-flex;
    align-items: center;
    gap: var(--s1);
    height: 20px;
    padding: 0 var(--s2);
    border-radius: 4px;
    border: 1px solid var(--line);
    font-size: var(--f-micro);
    font-weight: 500;
    color: var(--ink-dim);
    white-space: nowrap;
    line-height: 1;
  }
  .chip.mono { font-family: var(--mono); letter-spacing: var(--track-label); text-transform: uppercase; }
  .plate { background: var(--bone); color: var(--ink-on-bone); border-color: var(--bone); }
  .alert { color: var(--alert); border-color: color-mix(in srgb, var(--alert) 50%, transparent); }
  .quiet { border-color: transparent; background: var(--tint10); }
</style>
