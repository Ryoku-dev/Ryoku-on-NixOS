<!-- A choice among modes. The active segment is a bone plate (inversion),
     the rest hairline; the plate slides to the chosen segment. -->
<script lang="ts">
  import { ToggleGroup } from "bits-ui";

  interface Option {
    value: string;
    label: string;
    hint?: string;
  }

  interface Props {
    options: Option[];
    value: string;
    onchange?: (value: string) => void;
    size?: "sm" | "md";
    label?: string;
  }

  let { options, value = $bindable(), onchange, size = "md", label }: Props = $props();
</script>

<ToggleGroup.Root
  type="single"
  bind:value
  onValueChange={(v) => {
    if (v) onchange?.(v);
  }}
  class="seg {size}"
  aria-label={label}
>
  {#each options as o (o.value)}
    <ToggleGroup.Item value={o.value} class="seg-item" title={o.hint}>
      {o.label}
    </ToggleGroup.Item>
  {/each}
</ToggleGroup.Root>

<style>
  :global(.seg) {
    display: inline-flex;
    padding: 2px;
    gap: 2px;
    border: 1px solid var(--line);
    border-radius: var(--radius);
    background: transparent;
  }
  :global(.seg-item) {
    height: 26px;
    padding: 0 var(--s3);
    border-radius: 4px;
    font-size: var(--f-small);
    font-weight: 500;
    color: var(--ink-dim);
    white-space: nowrap;
    transition: background-color var(--t-fast) var(--ease), color var(--t-fast) var(--ease);
  }
  :global(.seg.sm .seg-item) { height: 22px; padding: 0 var(--s2); font-size: var(--f-micro); }
  :global(.seg-item:hover) { color: var(--ink); background: var(--tint5); }
  :global(.seg-item[data-state="on"]) { background: var(--bone); color: var(--ink-on-bone); }
</style>
