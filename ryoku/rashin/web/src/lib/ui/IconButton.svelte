<!-- A square hairline button for one glyph, always named: the tooltip is the
     label, and assistive tech reads it. -->
<script lang="ts">
  import type { HTMLButtonAttributes } from "svelte/elements";
  import Icon from "./Icon.svelte";
  import Tooltip from "./Tooltip.svelte";
  import type { IconName } from "./icons";

  interface Props extends HTMLButtonAttributes {
    icon: IconName;
    label: string;
    active?: boolean;
    size?: number;
    armed?: boolean;
    tip?: boolean;
  }

  let { icon, label, active = false, size = 30, armed = true, tip = true, class: cls = "", ...rest }: Props = $props();
</script>

{#snippet button()}
  <button
    class="ib {cls}"
    class:active
    aria-label={label}
    aria-pressed={active || undefined}
    disabled={!armed || rest.disabled}
    style:width="{size}px"
    style:height="{size}px"
    {...rest}
  >
    <Icon name={icon} size={Math.round(size * 0.53)} />
  </button>
{/snippet}

{#if tip}
  <Tooltip text={label}>{@render button()}</Tooltip>
{:else}
  {@render button()}
{/if}

<style>
  .ib {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    border-radius: var(--radius);
    border: 1px solid var(--line);
    color: var(--ink-dim);
    background: transparent;
    flex: none;
    transition: background-color var(--t-fast) var(--ease), color var(--t-fast) var(--ease), border-color var(--t-fast) var(--ease), transform var(--t-fast) var(--ease);
  }
  .ib:hover:not(:disabled) { background: var(--tint10); color: var(--ink); border-color: var(--line-strong); }
  .ib:active:not(:disabled) { transform: scale(0.96); }
  .ib.active { background: var(--bone); color: var(--ink-on-bone); border-color: var(--bone); }
  .ib:disabled { opacity: 0.4; cursor: default; }
</style>
