<!-- Only for a true binary. The knob is the one true circle in the kit. -->
<script lang="ts">
  import { Switch } from "bits-ui";

  interface Props {
    checked: boolean;
    onchange?: (checked: boolean) => void;
    label: string;
    disabled?: boolean;
  }

  let { checked = $bindable(), onchange, label, disabled = false }: Props = $props();
</script>

<Switch.Root bind:checked onCheckedChange={(c) => onchange?.(c)} {disabled} class="sw" aria-label={label}>
  <Switch.Thumb class="sw-knob" />
</Switch.Root>

<style>
  :global(.sw) {
    position: relative;
    width: 38px;
    height: 22px;
    border-radius: 11px;
    border: 1px solid var(--line-strong);
    background: transparent;
    padding: 0;
    flex: none;
    transition: background-color var(--t-mid) var(--ease), border-color var(--t-mid) var(--ease);
  }
  :global(.sw[data-state="checked"]) { background: var(--bone); border-color: var(--bone); }
  :global(.sw:disabled) { opacity: 0.4; cursor: default; }
  :global(.sw-knob) {
    position: absolute;
    top: 3px;
    left: 3px;
    width: 14px;
    height: 14px;
    border-radius: 50%;
    background: var(--ink-dim);
    transition: transform var(--t-mid) var(--ease-out), background-color var(--t-mid) var(--ease);
  }
  :global(.sw[data-state="checked"] .sw-knob) { transform: translateX(16px); background: var(--ink-on-bone); }
</style>
