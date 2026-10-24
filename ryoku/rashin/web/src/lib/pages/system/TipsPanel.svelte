<script lang="ts">
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import type { FixRequest, FixState } from "$lib/pages/overview/types";
  import type { Tip } from "./types";

  interface Props {
    tips: Tip[];
    states: Record<string, FixState>;
    copied: string;
    oncopy: (key: string, text: string) => void;
    onfix: (key: string, request: FixRequest) => void;
  }

  let { tips, states, copied, oncopy, onfix }: Props = $props();
</script>

<div class="intro">
  <strong>Read-only guidance</strong>
  <p>Rashin never executes a tip. Copy a command to inspect it yourself, or open an agent that reads the evidence and asks before it changes anything.</p>
</div>

{#if tips.length}
  <div class="tips">
    {#each tips as tip (tip.id)}
      {@const state = states[`tip:${tip.id}`] ?? { phase: "idle" }}
      <article class:urgent={tip.severity === "act"}>
        <div class="tip-head">
          <Chip tone={tip.severity === "act" ? "alert" : tip.severity === "watch" ? "quiet" : "line"}>{tip.severity === "act" ? "Act" : tip.severity === "watch" ? "Watch" : "Info"}</Chip>
          <h3>{tip.title}</h3>
        </div>
        <p>{tip.detail}</p>
        <div class="actions">
          {#if tip.command}
            <Button class="command" variant="line" icon={copied === `tip:${tip.id}` ? "check" : "copy"} onclick={() => oncopy(`tip:${tip.id}`, tip.command ?? "")}>
              <code>$ {tip.command}</code><span>{copied === `tip:${tip.id}` ? "Copied" : "Copy"}</span>
            </Button>
          {/if}
          <Button
            variant="plate"
            icon="spark"
            busy={state.phase === "opening"}
            onclick={() => onfix(`tip:${tip.id}`, { kind: "tip", id: tip.id })}
          >{state.phase === "opening" ? "Opening the agent" : "Fix with AI"}</Button>
        </div>
        {#if state.phase !== "idle" && state.phase !== "opening"}<p class="state" class:failed={state.phase === "failed"}>{state.message}</p>{/if}
      </article>
    {/each}
  </div>
{:else}
  <Empty title="Nothing needs attention" body="The deterministic system scan has no tips for this snapshot." icon="check" />
{/if}

<style>
  .intro { display: flex; align-items: baseline; gap: var(--s4); margin-bottom: var(--s4); padding: var(--s3) var(--s4); border: 1px solid var(--line-soft); border-radius: var(--radius); }
  .intro strong { flex: none; color: var(--ink); font-size: var(--f-small); font-weight: 500; }
  .intro p { color: var(--ink-mute); font-size: var(--f-small); }
  .tips { display: flex; flex-direction: column; gap: var(--s2); }
  article { position: relative; padding: var(--s4) var(--s5); border: 1px solid var(--line-soft); border-radius: var(--radius); }
  article.urgent { border-left-color: var(--alert); }
  .tip-head { display: flex; align-items: center; gap: var(--s3); }
  h3 { color: var(--ink); font-size: var(--f-row); font-weight: 500; }
  article > p { margin-top: var(--s2); max-width: 80ch; color: var(--ink-mute); font-size: var(--f-small); }
  .actions { display: flex; align-items: center; gap: var(--s2); margin-top: var(--s3); }
  :global(.command) { flex: 1; min-width: 0; max-width: 78ch; justify-content: flex-start; }
  :global(.command code) { min-width: 0; overflow: hidden; color: var(--ink); font-size: var(--f-micro); text-overflow: ellipsis; white-space: nowrap; }
  :global(.command span:last-child) { margin-left: auto; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); letter-spacing: var(--track-label); text-transform: uppercase; }
  article > .state { color: var(--ink-mute); font-size: var(--f-small); }
  article > .state.failed { color: var(--alert); }
  @media (max-width: 720px) { .intro, .actions { align-items: stretch; flex-direction: column; } }
</style>
