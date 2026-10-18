<script lang="ts">
  import type { Item, Permission } from "$chatstate";
  import type { CommandInfo, ModelInfo } from "$lib/chat/protocol";
  import Chip from "$lib/ui/Chip.svelte";
  import Fold from "$lib/ui/Fold.svelte";
  import Icon from "$lib/ui/Icon.svelte";
  import IconButton from "$lib/ui/IconButton.svelte";
  import Kbd from "$lib/ui/Kbd.svelte";
  import { tokenLabel, toolIcon } from "./presentation";

  interface ToolGroup {
    kind: string;
    total: number;
    completed: number;
    failed: number;
    live: number;
  }

  interface Props {
    session: { id: string; title: string };
    cwd?: string;
    agent: string;
    currentModel: string;
    pick: string;
    pickUnavailable: boolean;
    models: ModelInfo[];
    usage: { size: number; used: number } | null;
    items: Item[];
    /** the agent is mid-turn, so a live tool is really running */
    busy?: boolean;
    permissions: Permission[];
    commands: CommandInfo[];
    oncollapse: () => void;
  }

  let { session, cwd, agent, currentModel, pick, pickUnavailable, models, usage, items, permissions, commands, oncollapse, busy = false }: Props = $props();

  const modelName = $derived(models.find((model) => model.id === currentModel)?.name || currentModel || "Not selected");
  const usagePercent = $derived(usage && usage.size > 0 ? Math.min(100, (usage.used / usage.size) * 100) : 0);
  const toolGroups = $derived.by(() => {
    const groups = new Map<string, ToolGroup>();
    for (const item of items) {
      if (item.kind !== "tool") continue;
      const kind = item.kind2 || "other";
      const group = groups.get(kind) ?? { kind, total: 0, completed: 0, failed: 0, live: 0 };
      group.total += 1;
      if (item.status === "completed") group.completed += 1;
      else if (item.status === "failed") group.failed += 1;
      else if (item.status === "pending" || item.status === "in_progress") group.live += 1;
      groups.set(kind, group);
    }
    return [...groups.values()].sort((left, right) => right.total - left.total || left.kind.localeCompare(right.kind));
  });
</script>

<aside class="inspector" aria-label="Conversation inspector">
  <header class="pane-head">
    <IconButton icon="chevronRight" label="Collapse inspector" size={28} onclick={oncollapse} />
    <div>
      <span class="t-mark">Inspector</span>
      <Kbd keys={["Ctrl", "I"]} />
    </div>
  </header>

  <div class="inspector-scroll">
    <section class="inspector-section session-section">
      <span class="section-label">Session</span>
      <h3>{session.title || "New conversation"}</h3>
      {#if session.id}<p class="mono selectable">{session.id}</p>{/if}
      {#if cwd}<p class="mono cwd" title={cwd}>{cwd}</p>{/if}
    </section>

    <section class="inspector-section identity">
      <div class="fact"><span>Agent</span><strong>{agent || "Starting"}</strong></div>
      <div class="fact"><span>Model</span><strong title={currentModel}>{modelName}</strong></div>
      {#if pick}
        <div class="fact"><span>Pick</span><strong class:unavailable={pickUnavailable} title={pick}>{pick}{pickUnavailable ? " · unavailable" : ""}</strong></div>
      {/if}
    </section>

    {#if usage}
      <section class="inspector-section usage-section">
        <div class="usage-copy">
          <span>Context</span>
          <strong>{tokenLabel(usage.used)} / {tokenLabel(usage.size)}</strong>
        </div>
        <div class="bar"><i style:width={`${usagePercent}%`}></i></div>
      </section>
    {/if}

    <section class="inspector-section">
      <div class="section-head">
        <span class="section-label">Tools in this conversation</span>
        {#if permissions.length}<Chip tone="plate">{permissions.length} pending</Chip>{/if}
      </div>
      {#if toolGroups.length}
        <div class="tool-groups">
          {#each toolGroups as group (group.kind)}
            <div class="tool-group">
              <span class="kind"><Icon name={toolIcon(group.kind)} size={14} />{group.kind}</span>
              <span class="tool-count">{group.total}</span>
              <span class="status-counts">
                {#if group.live}<Chip tone={busy ? "line" : "quiet"}>{group.live} {busy ? "live" : "unfinished"}</Chip>{/if}
                {#if group.completed}<Chip tone="quiet">{group.completed} done</Chip>{/if}
                {#if group.failed}<Chip tone="alert">{group.failed} failed</Chip>{/if}
              </span>
            </div>
          {/each}
        </div>
      {:else}
        <p class="empty-copy">Tools used in this chat will appear here.</p>
      {/if}
    </section>

    <section class="inspector-section commands-section">
      <Fold>
        {#snippet summary()}
          <span class="fold-title">Slash commands <span>{commands.length}</span></span>
        {/snippet}
        {#if commands.length}
          <div class="command-list">
            {#each commands as command (command.name)}
              <div class="command">
                <code>/{command.name.replace(/^\//, "")}</code>
                <span>{command.description}</span>
              </div>
            {/each}
          </div>
        {:else}
          <p class="empty-copy">The active agent has not advertised commands.</p>
        {/if}
      </Fold>
    </section>
  </div>
</aside>

<style>
  .inspector { display: flex; flex-direction: column; width: 300px; min-width: 300px; min-height: 0; border-left: 1px solid var(--line-soft); background: var(--paper); }
  .pane-head { display: flex; align-items: center; justify-content: space-between; gap: var(--s3); min-height: 61px; padding: var(--s4); border-bottom: 1px solid var(--line-soft); }
  .pane-head > div { display: flex; align-items: center; gap: var(--s2); }
  .inspector-scroll { flex: 1; min-height: 0; overflow-y: auto; }
  .inspector-section { padding: var(--s4); border-bottom: 1px solid var(--line-soft); }
  .section-label { color: var(--ink-mute); font-size: var(--f-small); }
  .session-section h3 { margin-top: var(--s2); color: var(--ink); font-size: var(--f-row); font-weight: 500; }
  .mono { margin-top: var(--s1); overflow: hidden; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); text-overflow: ellipsis; white-space: nowrap; }
  .selectable { user-select: text; }
  .cwd { margin-top: var(--s2); color: var(--ink-mute); }
  .identity { display: flex; flex-direction: column; gap: var(--s3); }
  .fact { display: grid; grid-template-columns: 64px minmax(0, 1fr); gap: var(--s3); font-size: var(--f-small); }
  .fact span { color: var(--ink-mute); }
  .fact strong { overflow: hidden; color: var(--ink); font-weight: 500; text-overflow: ellipsis; white-space: nowrap; }
  .fact strong.unavailable { color: var(--alert); white-space: normal; }
  .usage-copy { display: flex; justify-content: space-between; gap: var(--s3); margin-bottom: var(--s2); font-size: var(--f-small); }
  .usage-copy span { color: var(--ink-mute); }
  .usage-copy strong { color: var(--ink); font-family: var(--mono); font-size: var(--f-micro); font-weight: 400; }
  .section-head { display: flex; align-items: center; justify-content: space-between; gap: var(--s2); margin-bottom: var(--s3); }
  .tool-groups { display: flex; flex-direction: column; }
  .tool-group { display: grid; grid-template-columns: minmax(72px, 1fr) auto; gap: var(--s2); padding: var(--s2) 0; border-top: 1px solid var(--line-soft); }
  .tool-group:first-child { border-top: 0; }
  .kind { display: flex; align-items: center; gap: var(--s2); color: var(--ink-dim); font-size: var(--f-small); text-transform: capitalize; }
  .tool-count { color: var(--ink); font-family: var(--mono); font-size: var(--f-small); }
  .status-counts { grid-column: 1 / -1; display: flex; flex-wrap: wrap; gap: var(--s1); padding-left: 22px; }
  .empty-copy { color: var(--ink-faint); font-size: var(--f-small); }
  .commands-section { padding-top: var(--s3); }
  .fold-title { display: flex; justify-content: space-between; width: 100%; color: var(--ink-mute); }
  .fold-title span { font-family: var(--mono); color: var(--ink-faint); }
  .command-list { display: flex; flex-direction: column; gap: var(--s2); padding: var(--s2) 0 0 22px; }
  .command { display: flex; flex-direction: column; gap: 2px; }
  .command code { color: var(--ink); font-size: var(--f-small); }
  .command span { color: var(--ink-faint); font-size: var(--f-micro); }
</style>
