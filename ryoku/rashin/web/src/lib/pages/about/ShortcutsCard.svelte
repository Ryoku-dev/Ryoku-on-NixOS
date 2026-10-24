<script lang="ts">
  import Card from "$lib/ui/Card.svelte";
  import Kbd from "$lib/ui/Kbd.svelte";

  const shortcuts = [
    { keys: ["Alt", "Space"], label: "Open the quick Ask bar" },
    { keys: ["Super", "Alt", "Space"], label: "Open this console window" },
    { keys: ["Ctrl", "N"], label: "Start a new chat" },
    { keys: ["Ctrl", "K"], label: "Open chat history" },
    { keys: ["Ctrl", "B"], label: "Toggle the chat rail" },
    { keys: ["Ctrl", "I"], label: "Focus the chat composer" },
  ];
</script>

<Card title="Shortcuts" gloss="鍵" lead="The console's own keys, in one place.">
  <div class="shortcuts">
    {#each shortcuts as shortcut (shortcut.label)}
      <div><span>{shortcut.label}</span><Kbd keys={shortcut.keys} /></div>
    {/each}
  </div>
</Card>

<style>
  .shortcuts { display: grid; }
  .shortcuts > div { display: flex; align-items: center; justify-content: space-between; gap: var(--s4); min-height: 40px; border-bottom: 1px solid var(--line-soft); }
  .shortcuts > div:last-child { border-bottom: 0; }
  .shortcuts span { color: var(--ink-dim); font-size: var(--f-small); }
</style>
