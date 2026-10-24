<script lang="ts">
  import type { MsgItem } from "$chatstate";
  import Markdown from "$lib/content/Markdown.svelte";
  import NeedleFace from "$lib/fx/NeedleFace.svelte";
  import ThinkingOrb from "$lib/fx/ThinkingOrb.svelte";
  import Fold from "$lib/ui/Fold.svelte";

  interface Props {
    item: MsgItem;
    /** the conversation the face stands for */
    seed: string;
  }

  let { item, seed }: Props = $props();
  let thoughtOpen = $state(false);
  let answerStarted = $state(false);

  $effect(() => {
    if (item.thought && item.open && !item.text && !answerStarted) thoughtOpen = true;
    if (item.text && !answerStarted) thoughtOpen = false;
    answerStarted = Boolean(item.text);
  });
</script>

{#if item.role === "user"}
  <article class="message user-message">
    <div class="user-plate">
      {#if item.images.length}
        <div class="prompt-images">
          {#each item.images as image, index (`${image.data.slice(0, 20)}:${index}`)}
            <img src={`data:${image.mimeType};base64,${image.data}`} alt="Attached prompt" />
          {/each}
        </div>
      {/if}
      {#if item.text}<p>{item.text}</p>{/if}
    </div>
  </article>
{:else}
  <article class="message agent-message" class:continued={item.cont}>
    {#if !item.cont}
      <header class="agent-head">
        <NeedleFace {seed} size={28} mood={item.open ? (item.text ? "working" : "thinking") : "idle"} follow={false} label="The Needle" />
        <span>The Needle</span>
      </header>
    {/if}
    <div class="agent-body">
      {#if item.thought}
        <Fold bind:open={thoughtOpen} class="thought-fold">
          {#snippet summary()}
            <span class="thought-summary">
              {#if item.open && !item.text}<ThinkingOrb mode="breathing" size={20} label="Thinking" />{/if}
              <span class="thought-title">Thinking</span>
              {#if !thoughtOpen}<span class="thought-preview">{item.thought.replace(/\s+/g, " ").trim()}</span>{/if}
            </span>
          {/snippet}
          <div class="thought-copy">{item.thought}</div>
        </Fold>
      {/if}
      {#if item.text}
        <div class="answer">
          <Markdown source={item.text} breaks />
          {#if item.open}<span class="stream-caret" aria-label="Still writing"></span>{/if}
        </div>
      {/if}
      {#if item.failed}<p class="failed">The answer stopped before it completed.</p>{/if}
    </div>
  </article>
{/if}

<style>
  .message { width: 100%; animation: item-in var(--t-mid) var(--ease-out); }
  .user-message { display: flex; justify-content: flex-end; }
  .user-plate {
    display: flex;
    flex-direction: column;
    gap: var(--s3);
    max-width: 62%;
    padding: var(--s3) var(--s4);
    border-radius: var(--radius);
    background: var(--bone);
    color: var(--ink-on-bone);
    line-height: 1.55;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .prompt-images { display: flex; flex-wrap: wrap; gap: var(--s2); }
  .prompt-images img { width: 112px; height: 80px; border: 1px solid color-mix(in srgb, var(--ink-on-bone) 25%, transparent); border-radius: 4px; object-fit: cover; }
  .agent-message { display: flex; flex-direction: column; gap: var(--s3); }
  .agent-message.continued { margin-top: calc(-1 * var(--s2)); }
  .agent-head { display: flex; align-items: center; gap: var(--s3); color: var(--ink); font-size: var(--f-row); font-weight: 500; }
  .agent-body { padding-left: 40px; }
  .continued .agent-body { padding-left: 40px; }
  :global(.thought-fold) { margin-bottom: var(--s4); }
  .thought-summary { display: flex; align-items: center; gap: var(--s2); min-width: 0; }
  .thought-title { flex: none; color: var(--ink-dim); }
  .thought-preview { overflow: hidden; min-width: 0; color: var(--ink-faint); text-overflow: ellipsis; white-space: nowrap; }
  .thought-copy {
    margin: var(--s2) 0 0 22px;
    padding-left: var(--s3);
    border-left: 1px solid var(--line);
    color: var(--ink-mute);
    font-size: var(--f-small);
    line-height: 1.6;
    white-space: pre-wrap;
    overflow-wrap: anywhere;
  }
  .answer { position: relative; }
  .stream-caret {
    display: inline-block;
    width: 1px;
    height: 1.1em;
    margin-left: 3px;
    vertical-align: -0.15em;
    background: var(--ink-mute);
    animation: caret 900ms steps(2, end) infinite;
  }
  .failed { margin-top: var(--s3); color: var(--alert); font-size: var(--f-small); }
  @keyframes item-in { from { opacity: 0; transform: translateY(4px); } }
  @keyframes caret { 50% { opacity: 0.25; } }
  @media (max-width: 760px) {
    .user-plate { max-width: 82%; }
    .agent-body, .continued .agent-body { padding-left: 0; }
  }
</style>
