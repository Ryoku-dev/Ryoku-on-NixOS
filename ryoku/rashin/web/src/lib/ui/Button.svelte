<!-- The one button. `plate` is the bone inversion (the primary action),
     `line` a hairline, `quiet` text alone. `armed` is the ui-ux rule that a
     control with nothing to act on is never offered as live. -->
<script lang="ts">
  import type { Snippet } from "svelte";
  import type { HTMLButtonAttributes } from "svelte/elements";
  import Icon from "./Icon.svelte";
  import type { IconName } from "./icons";

  interface Props extends HTMLButtonAttributes {
    variant?: "plate" | "line" | "quiet";
    size?: "sm" | "md";
    icon?: IconName;
    armed?: boolean;
    busy?: boolean;
    children?: Snippet;
  }

  let { variant = "line", size = "md", icon, armed = true, busy = false, children, class: cls = "", ...rest }: Props = $props();
</script>

<button
  class="btn {variant} {size} {cls}"
  class:busy
  disabled={!armed || busy || rest.disabled}
  aria-busy={busy || undefined}
  {...rest}
>
  {#if icon}<Icon name={icon} size={size === "sm" ? 14 : 16} />{/if}
  {#if children}<span class="label">{@render children()}</span>{/if}
</button>

<style>
  .btn {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    gap: var(--s2);
    height: 32px;
    padding: 0 var(--s4);
    border-radius: var(--radius);
    border: 1px solid transparent;
    font-family: var(--ui);
    font-size: var(--f-body);
    font-weight: 500;
    line-height: 1;
    color: var(--ink);
    white-space: nowrap;
    transition: background-color var(--t-fast) var(--ease), border-color var(--t-fast) var(--ease), color var(--t-fast) var(--ease), transform var(--t-fast) var(--ease);
    user-select: none;
  }
  .btn.sm { height: var(--ctl-h); padding: 0 var(--s3); font-size: var(--f-small); }
  .btn:active:not(:disabled) { transform: translateY(1px); }
  .btn:disabled { opacity: 0.45; cursor: default; }

  .plate { background: var(--bone); color: var(--ink-on-bone); border-color: var(--bone); }
  .plate:hover:not(:disabled) { background: color-mix(in srgb, var(--bone) 88%, var(--paper)); }

  .line { border-color: var(--line); background: transparent; }
  .line:hover:not(:disabled) { background: var(--tint10); border-color: var(--line-strong); }

  .quiet { color: var(--ink-dim); padding: 0 var(--s2); }
  .quiet:hover:not(:disabled) { color: var(--ink); background: var(--tint5); }

  .label { display: inline-block; }
</style>
