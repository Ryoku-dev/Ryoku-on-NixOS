<!-- A list to pick one value from, as a popover of rows. -->
<script lang="ts">
  import { Select } from "bits-ui";
  import Icon from "./Icon.svelte";

  interface Option {
    value: string;
    label: string;
    hint?: string;
  }

  interface Props {
    options: Option[];
    value: string;
    onchange?: (value: string) => void;
    placeholder?: string;
    label: string;
    size?: "sm" | "md";
    disabled?: boolean;
  }

  let { options, value = $bindable(), onchange, placeholder = "Choose", label, size = "md", disabled = false }: Props = $props();
  const current = $derived(options.find((o) => o.value === value));
</script>

<Select.Root type="single" bind:value onValueChange={(v) => onchange?.(v)} {disabled}>
  <Select.Trigger class="sel {size}" aria-label={label}>
    <span class="sel-value" class:placeholder={!current}>{current?.label ?? placeholder}</span>
    <Icon name="chevronDown" size={14} />
  </Select.Trigger>
  <Select.Portal>
    <Select.Content class="sel-menu" sideOffset={4}>
      <Select.Viewport>
        {#each options as o (o.value)}
          <Select.Item value={o.value} label={o.label} class="sel-item">
            {#snippet children({ selected })}
              <span class="sel-item-label">{o.label}</span>
              {#if o.hint}<span class="sel-item-hint">{o.hint}</span>{/if}
              {#if selected}<Icon name="check" size={14} />{/if}
            {/snippet}
          </Select.Item>
        {/each}
      </Select.Viewport>
    </Select.Content>
  </Select.Portal>
</Select.Root>

<style>
  :global(.sel) {
    display: inline-flex;
    align-items: center;
    gap: var(--s2);
    height: 32px;
    max-width: 100%;
    padding: 0 var(--s2) 0 var(--s3);
    border: 1px solid var(--line);
    border-radius: var(--radius);
    color: var(--ink);
    font-size: var(--f-body);
    background: transparent;
    transition: border-color var(--t-fast) var(--ease), background-color var(--t-fast) var(--ease);
  }
  :global(.sel.sm) { height: var(--ctl-h); font-size: var(--f-small); }
  :global(.sel:hover) { border-color: var(--line-strong); background: var(--tint5); }
  :global(.sel[data-state="open"]) { border-color: var(--bone); }
  .sel-value { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sel-value.placeholder { color: var(--ink-mute); }
  :global(.sel-menu) {
    z-index: 50;
    min-width: var(--bits-select-anchor-width);
    max-height: var(--bits-select-content-available-height, 320px);
    overflow: auto;
    padding: var(--s1);
    border: 1px solid var(--line-strong);
    border-radius: var(--radius);
    background: var(--paper-lift);
    animation: menu-in var(--t-fast) var(--ease-out);
  }
  @keyframes menu-in { from { opacity: 0; transform: translateY(-4px); } to { opacity: 1; transform: none; } }
  :global(.sel-item) {
    display: flex;
    align-items: center;
    gap: var(--s3);
    min-height: 32px;
    padding: var(--s1) var(--s2);
    border-radius: 4px;
    color: var(--ink-dim);
    font-size: var(--f-body);
    cursor: pointer;
  }
  :global(.sel-item[data-highlighted]) { background: var(--tint10); color: var(--ink); }
  :global(.sel-item[data-selected]) { color: var(--ink); }
  .sel-item-label { flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sel-item-hint { color: var(--ink-faint); font-size: var(--f-micro); font-family: var(--mono); }
</style>
