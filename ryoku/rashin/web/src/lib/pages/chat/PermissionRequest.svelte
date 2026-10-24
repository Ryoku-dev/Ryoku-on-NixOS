<script lang="ts">
  import type { Permission } from "$chatstate";
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";

  interface Props {
    permission: Permission;
    onanswer: (requestId: string, optionId: string) => void;
  }

  let { permission, onanswer }: Props = $props();
</script>

<section class="permission" aria-label="Approval required">
  <header>
    <div>
      <span class="permission-kicker">Approval required</span>
      <h4>{permission.title || "Tool request"}</h4>
    </div>
    {#if permission.kind}<Chip mono>{permission.kind}</Chip>{/if}
  </header>
  {#if permission.input}<pre>{permission.input}</pre>{/if}
  <div class="permission-actions">
    {#each permission.options as option (option.id)}
      <Button
        size="sm"
        variant={option.kind === "allow_once" || option.id === "allow_once" ? "plate" : "line"}
        onclick={() => onanswer(permission.requestId, option.id)}
      >{option.name}</Button>
    {/each}
  </div>
</section>

<style>
  .permission {
    display: flex;
    flex-direction: column;
    gap: var(--s3);
    margin-top: var(--s3);
    padding: var(--s3) var(--s4);
    border: 1px solid var(--line-strong);
    border-left: 2px solid var(--bone);
    border-radius: var(--radius);
    animation: permission-in var(--t-mid) var(--ease-out);
  }
  header { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--s3); }
  .permission-kicker { display: block; margin-bottom: var(--s1); color: var(--ink-mute); font-size: var(--f-small); }
  h4 { color: var(--ink); font-size: var(--f-body); font-weight: 500; }
  pre {
    max-height: 144px;
    overflow: auto;
    padding: var(--s2) var(--s3);
    border: 1px solid var(--line-soft);
    border-radius: 4px;
    background: var(--paper-lift);
    color: var(--ink-dim);
    font-size: var(--f-small);
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .permission-actions { display: flex; flex-wrap: wrap; gap: var(--s2); }
  @keyframes permission-in { from { opacity: 0; transform: translateY(4px); } }
</style>
