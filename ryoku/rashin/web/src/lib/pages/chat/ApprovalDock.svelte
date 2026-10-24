<!-- An approval the user cannot scroll past. While the agent waits on a
     person, the first open request docks above the composer with its
     options; the composer beam turns to a pulse so the eye lands here, and a
     desktop notification fires if the window is not in front. The inline
     request on the tool row stays, this is the one that gets answered. -->
<script lang="ts">
  import type { Permission } from "$chatstate";
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Kbd from "$lib/ui/Kbd.svelte";

  interface Props {
    permissions: Permission[];
    onanswer: (requestId: string, optionId: string) => void;
  }

  let { permissions, onanswer }: Props = $props();

  const first = $derived(permissions[0]);
  const allow = $derived(first?.options.find((o) => o.kind === "allow_once" || o.id === "allow_once"));
  const reject = $derived(first?.options.find((o) => o.kind === "reject_once" || o.id === "reject_once" || /reject|deny/i.test(o.name)));

  let notified = $state("");

  $effect(() => {
    if (!first || notified === first.requestId) return;
    notified = first.requestId;
    if (document.hasFocus() || typeof Notification === "undefined" || Notification.permission !== "granted") return;
    const n = new Notification("Rashin needs a decision", {
      body: first.title || "The agent is waiting for an approval",
      tag: "rashin-approval",
    });
    n.onclick = () => window.focus();
  });

  function handleKey(e: KeyboardEvent) {
    if (!first || e.ctrlKey || e.metaKey || e.altKey) return;
    const target = e.target as HTMLElement | null;
    if (target && (target.tagName === "TEXTAREA" || target.tagName === "INPUT")) return;
    if (e.key === "y" && allow) {
      e.preventDefault();
      onanswer(first.requestId, allow.id);
    } else if (e.key === "n" && reject) {
      e.preventDefault();
      onanswer(first.requestId, reject.id);
    }
  }
</script>

<svelte:window onkeydown={handleKey} />

{#if first}
  <div class="dock" role="alertdialog" aria-live="assertive" aria-label="Approval needed">
    <div class="dock-head">
      <span class="dock-mark" aria-hidden="true">力</span>
      <div class="dock-text">
        <span class="dock-kicker">Waiting for you{permissions.length > 1 ? ` · ${permissions.length} requests` : ""}</span>
        <span class="dock-title">{first.title || "Tool request"}</span>
      </div>
      {#if first.kind}<Chip mono>{first.kind}</Chip>{/if}
    </div>
    {#if first.input}<pre class="dock-input">{first.input}</pre>{/if}
    <div class="dock-actions">
      {#each first.options as option (option.id)}
        <Button
          size="sm"
          variant={option === allow ? "plate" : "line"}
          onclick={() => onanswer(first.requestId, option.id)}
        >{option.name}</Button>
      {/each}
      <span class="dock-keys">
        {#if allow}<Kbd keys={["Y"]} /> allow once{/if}
        {#if reject}<Kbd keys={["N"]} /> reject{/if}
      </span>
    </div>
  </div>
{/if}

<style>
  .dock {
    display: flex;
    flex-direction: column;
    gap: var(--s3);
    width: min(100%, var(--measure));
    margin: 0 auto;
    padding: var(--s3) var(--s4);
    border: 1px solid var(--bone);
    border-radius: var(--radius);
    background: var(--paper-lift);
    animation: dock-in var(--t-mid) var(--ease-out);
  }
  @keyframes dock-in { from { opacity: 0; transform: translateY(8px); } }
  .dock-head { display: flex; align-items: center; gap: var(--s3); }
  .dock-mark {
    display: inline-flex;
    align-items: center;
    justify-content: center;
    width: 26px;
    height: 26px;
    border-radius: 6px;
    background: var(--sun);
    color: #fff;
    font-family: var(--jp);
    font-weight: 700;
    font-size: 14px;
    flex: none;
    animation: mark-breathe 1.8s var(--ease) infinite;
  }
  @keyframes mark-breathe { 0%, 100% { opacity: 1; } 50% { opacity: 0.55; } }
  .dock-text { display: flex; flex-direction: column; min-width: 0; flex: 1; }
  .dock-kicker { color: var(--ink-mute); font-size: var(--f-small); }
  .dock-title { color: var(--ink); font-size: var(--f-row); font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .dock-input {
    max-height: 96px;
    overflow: auto;
    padding: var(--s2) var(--s3);
    border: 1px solid var(--line-soft);
    border-radius: 4px;
    background: var(--paper);
    color: var(--ink-dim);
    font-size: var(--f-small);
    line-height: 1.5;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .dock-actions { display: flex; flex-wrap: wrap; align-items: center; gap: var(--s2); }
  .dock-keys { display: inline-flex; align-items: center; gap: var(--s2); margin-left: auto; color: var(--ink-faint); font-size: var(--f-micro); }
</style>
