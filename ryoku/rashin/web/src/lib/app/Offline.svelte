<!-- The daemon went away. Says so once, quietly, and goes when it is back. -->
<script lang="ts">
  import { machine } from "$lib/state/machine.svelte";
  import ThinkingOrb from "$lib/fx/ThinkingOrb.svelte";
</script>

{#if !machine.online}
  <div class="offline" role="status">
    <ThinkingOrb mode="connecting" size={20} />
    <span>The Rashin daemon is not answering. Reconnecting; <code>systemctl --user status ryoku-rashin</code> says why.</span>
  </div>
{/if}

<style>
  .offline {
    position: fixed;
    left: 50%;
    bottom: var(--s5);
    transform: translateX(-50%);
    display: flex;
    align-items: center;
    gap: var(--s3);
    padding: var(--s2) var(--s4);
    border: 1px solid var(--line-strong);
    border-radius: var(--island-radius);
    background: var(--paper-lift);
    color: var(--ink-dim);
    font-size: var(--f-small);
    z-index: 30;
    animation: rise var(--t-mid) var(--ease-out);
  }
  code { color: var(--ink); font-size: var(--f-small); }
  @keyframes rise { from { opacity: 0; transform: translate(-50%, 8px); } }
</style>
