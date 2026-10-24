<script lang="ts">
  import type { SessionMeta } from "$lib/chat/protocol";
  import type { ChatLane } from "$lib/chat/store.svelte";
  import Button from "$lib/ui/Button.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import IconButton from "$lib/ui/IconButton.svelte";
  import Kbd from "$lib/ui/Kbd.svelte";
  import { relativeTime } from "./presentation";

  interface Props {
    lane: ChatLane;
    sessions: SessionMeta[];
    currentId: string;
    terminalBusy?: boolean;
    terminalError?: string;
    onnew: () => void;
    onswitch: (id: string) => void;
    oncollapse: () => void;
    onterminal: () => void;
  }

  let { lane, sessions, currentId, terminalBusy = false, terminalError = "", onnew, onswitch, oncollapse, onterminal }: Props = $props();
</script>

<aside class="sessions" aria-label={`${lane === "ryoku" ? "Agent" : "Chat"} sessions`}>
  <header class="pane-head">
    <div>
      <span class="t-mark">Conversations</span>
      <span class="shortcut"><Kbd keys={["Ctrl", "B"]} /></span>
    </div>
    <IconButton icon="chevronLeft" label="Collapse conversations" size={28} onclick={oncollapse} />
  </header>

  <div class="session-actions">
    <Button variant="plate" icon="plus" onclick={onnew}>New chat</Button>
    <Button size="sm" busy={terminalBusy} onclick={onterminal}>Open in terminal</Button>
  </div>
  {#if terminalError}<p class="terminal-error" role="alert">{terminalError}</p>{/if}

  <div class="session-list">
    {#if sessions.length === 0}
      <Empty icon="history" title="No saved conversations" body="Start a chat and it will appear here." />
    {:else}
      <div class="plates">
        {#each sessions as session (session.id)}
          <button
            class="plate session"
            class:on={session.id === currentId}
            type="button"
            aria-current={session.id === currentId ? "page" : undefined}
            onclick={() => onswitch(session.id)}
          >
            <span class="session-copy">
              <span class="session-title">{session.title || "Untitled chat"}</span>
              {#if session.cwd}<span class="session-cwd">{session.cwd}</span>{/if}
            </span>
            {#if session.updatedAt}<time datetime={session.updatedAt}>{relativeTime(session.updatedAt)}</time>{/if}
          </button>
        {/each}
      </div>
    {/if}
  </div>
</aside>

<style>
  .sessions {
    display: flex;
    flex-direction: column;
    gap: var(--s4);
    width: var(--rail-w);
    min-width: var(--rail-w);
    min-height: 0;
    padding: var(--s4);
    border-right: 1px solid var(--line-soft);
    background: var(--paper);
  }
  .pane-head { display: flex; align-items: center; justify-content: space-between; gap: var(--s3); min-height: 28px; }
  .pane-head > div { display: flex; align-items: center; gap: var(--s2); }
  .shortcut { opacity: 0.72; }
  .session-actions { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: var(--s2); }
  .terminal-error { color: var(--alert); font-size: var(--f-small); line-height: 1.4; }
  .session-list { flex: 1; min-height: 0; overflow: auto; margin: 0 calc(-1 * var(--s2)); padding: 0 var(--s2); }
  .session { min-height: 52px; align-items: flex-start; }
  .session-copy { display: flex; flex: 1; min-width: 0; flex-direction: column; gap: 2px; }
  .session-title { overflow: hidden; color: inherit; font-size: var(--f-small); font-weight: 500; text-overflow: ellipsis; white-space: nowrap; }
  .session-cwd { overflow: hidden; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); text-overflow: ellipsis; white-space: nowrap; }
  .session.on .session-cwd { color: color-mix(in srgb, var(--ink-on-bone) 62%, transparent); }
  time { flex: none; padding-top: 2px; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); }
  .session.on time { color: color-mix(in srgb, var(--ink-on-bone) 62%, transparent); }
  :global(.sessions .empty) { padding: var(--s5) var(--s3); }
</style>
