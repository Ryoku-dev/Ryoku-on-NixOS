<script lang="ts">
  interface Props { keys: string[] }
  let { keys }: Props = $props();
</script>

<span class="kbd">
  {#each keys as k, i (i)}
    <kbd>{k}</kbd>
  {/each}
</span>

<style>
  .kbd { display: inline-flex; gap: 3px; vertical-align: middle; }
  kbd {
    display: inline-flex;
    align-items: center;
    height: 18px;
    padding: 0 5px;
    border: 1px solid var(--line);
    border-bottom-width: 2px;
    border-radius: 4px;
    font-family: var(--mono);
    font-size: var(--f-tiny);
    letter-spacing: 0.04em;
    color: var(--ink-mute);
    background: var(--tint5);
  }
</style>
