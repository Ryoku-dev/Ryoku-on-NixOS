<!-- A named input. The name sits above in the label voice; the control is a
     hairline box that brightens on focus. -->
<script lang="ts">
  import type { HTMLInputAttributes } from "svelte/elements";

  interface Props extends HTMLInputAttributes {
    label: string;
    hint?: string;
    value?: string;
    mono?: boolean;
  }

  let { label, hint, value = $bindable(""), mono = false, class: cls = "", ...rest }: Props = $props();
  const id = $props.id();
</script>

<div class="field {cls}">
  <label class="field-label t-label" for={id}>{label}</label>
  <input {id} class="field-input" class:mono bind:value {...rest} />
  {#if hint}<p class="field-hint">{hint}</p>{/if}
</div>

<style>
  .field { display: flex; flex-direction: column; gap: var(--s1); min-width: 0; }
  .field-input {
    height: 32px;
    padding: 0 var(--s3);
    border: 1px solid var(--line);
    border-radius: var(--radius);
    background: transparent;
    color: var(--ink);
    outline: none;
    transition: border-color var(--t-fast) var(--ease), background-color var(--t-fast) var(--ease);
  }
  .field-input.mono { font-family: var(--mono); font-size: var(--f-small); }
  .field-input::placeholder { color: var(--ink-faint); }
  .field-input:hover { border-color: var(--line-strong); }
  .field-input:focus { border-color: var(--bone); background: var(--tint5); }
  .field-hint { color: var(--ink-faint); font-size: var(--f-small); }
</style>
