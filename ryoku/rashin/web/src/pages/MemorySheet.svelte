<script lang="ts">
  import { onMount } from "svelte";
  import Page from "$lib/app/Page.svelte";
  import { api } from "$lib/api/client";
  import ActivityHeatmap from "$lib/pages/memory/ActivityHeatmap.svelte";
  import MemoryGraph from "$lib/pages/memory/MemoryGraph.svelte";
  import { buildGraphModel, type GraphNode, type HeatmapEntry } from "$lib/pages/memory/graph";
  import Button from "$lib/ui/Button.svelte";
  import Card from "$lib/ui/Card.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";

  interface MemorySession {
    id: string;
    title: string;
    model: string;
    messages: number;
    startedAt: string;
    source: string;
  }

  interface MemoryReport {
    provider: { kind: string; obsidianVault?: string };
    files: { memoryMd: boolean; memoryBytes: number; userMd: boolean };
    learned: {
      memoryEntries: number;
      userFacts: number;
      agentSkills: number;
      vaultNotes: number;
      journalDays: number;
      preview?: string[];
    };
    graph: {
      nodes: Array<{ id: string; label: string; group: string; size: number }>;
      links: Array<{ source: string; target: string }>;
    };
    heatmap: HeatmapEntry[];
    sessions: MemorySession[];
    sessionsNote?: string;
  }

  let report = $state<MemoryReport | null>(null);
  let selected = $state<GraphNode | null>(null);
  let loading = $state(true);
  let refreshing = $state(false);
  let error = $state("");
  const graph = $derived(buildGraphModel(report));
  const learnedTotal = $derived(report
    ? report.learned.memoryEntries + report.learned.userFacts + report.learned.agentSkills + report.learned.vaultNotes
    : 0);
  const hasMemory = $derived(Boolean(report && (
    report.files.memoryMd
    || learnedTotal
    || report.graph.nodes.length
    || report.sessions.length
    || report.heatmap.some((day) => (day.count || 0) > 0)
  )));
  const selectedConnections = $derived(selected
    ? graph.links.filter((link) => {
        const source = typeof link.source === "object" ? link.source.id : link.source;
        const target = typeof link.target === "object" ? link.target.id : link.target;
        return source === selected?.id || target === selected?.id;
      }).length
    : 0);

  function formatBytes(bytes: number): string {
    if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
    const units = ["B", "KB", "MB", "GB"];
    const power = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
    const value = bytes / 1024 ** power;
    return `${value >= 10 || power === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[power]}`;
  }

  function shortDate(value: string): string {
    const date = new Date(value);
    if (!value || Number.isNaN(date.getTime())) return "";
    return date.toLocaleDateString(undefined, { month: "short", day: "2-digit" });
  }

  async function load(force = false): Promise<void> {
    if (force) refreshing = true;
    else loading = true;
    error = "";
    try {
      report = await api.hermesMemory() as unknown as MemoryReport;
      selected = null;
    } catch {
      error = "The memory report is out of reach. Start the Rashin daemon, then refresh.";
    } finally {
      loading = false;
      refreshing = false;
    }
  }

  onMount(() => {
    void load();
  });
</script>

{#snippet tools()}
  <Button icon="refresh" size="sm" busy={refreshing} onclick={() => load(true)}>Refresh</Button>
{/snippet}

<Page title="Memory" gloss="記憶" lead="What Hermes retained, how it connects and when it grew." {tools}>
  {#if loading}
    <p class="loading">Reading Hermes memory…</p>
  {:else if error}
    <Empty icon="thought" title="Memory unavailable" body={error} />
  {:else if report && !hasMemory}
    <Empty
      icon="thought"
      title={report.sessionsNote ? "Hermes memory is empty" : "Hermes has no memory yet"}
      body={report.sessionsNote || "Memory, sessions and activity appear here after Hermes has retained its first notes."}
    />
  {:else if report}
    <div class="memory-sheet">
      <section class="readouts" aria-label="Memory summary">
        <div class="readout provider">
          <span class="t-label">Provider</span>
          <div class="readout-main"><Chip tone={report.provider.kind && report.provider.kind !== "builtin" ? "quiet" : "plate"} mono>{report.provider.kind || "none"}</Chip></div>
          <span class="readout-sub" title={report.provider.obsidianVault || ""}>{report.provider.obsidianVault || "No Obsidian vault"}</span>
        </div>
        <div class="readout">
          <span class="t-label">Learned</span>
          <strong class="readout-main">{learnedTotal}</strong>
          <span class="readout-sub">{report.learned.memoryEntries} memories / {report.learned.userFacts} facts / {report.learned.agentSkills} skills</span>
        </div>
        <div class="readout">
          <span class="t-label">memory.md</span>
          <strong class="readout-main">{report.files.memoryMd ? formatBytes(report.files.memoryBytes) : "Absent"}</strong>
          <span class="readout-sub">{report.files.userMd ? "User profile present" : "No user profile"}</span>
        </div>
        <div class="readout">
          <span class="t-label">Sessions</span>
          <strong class="readout-main">{report.sessions.length}</strong>
          <span class="readout-sub">{report.learned.journalDays} journal days</span>
        </div>
      </section>

      <div class="memory-grid">
        <Card title="Memory graph" gloss="連想" lead="Select a node to inspect its place in the vault." pad={false} class="graph-card">
          {#if graph.nodes.length}
            <MemoryGraph model={graph} selected={selected?.id} onselect={(node) => selected = node} />
          {:else}
            <div class="graph-empty"><Empty icon="link" title="No relationships yet" body="The graph appears after memory notes or vault references exist." /></div>
          {/if}
        </Card>

        <aside class="memory-side">
          <Card title="Selection" gloss="詳細">
            {#if selected}
              <div class="selection">
                <div class="selection-name">{selected.label}</div>
                <code>{selected.id}</code>
                <dl>
                  <div><dt>Kind</dt><dd>{selected.group || "note"}</dd></div>
                  <div><dt>Connections</dt><dd>{selectedConnections}</dd></div>
                  <div><dt>Bytes</dt><dd>{formatBytes(selected.size)}</dd></div>
                </dl>
              </div>
            {:else}
              <p class="side-empty">Select an ink dot to inspect that memory.</p>
            {/if}
          </Card>

          <Card title="Activity" gloss="活動" lead="The last 26 weeks.">
            <ActivityHeatmap entries={report.heatmap} />
          </Card>

          <Card title="Hermes sessions" gloss="履歴">
            {#if report.sessions.length}
              <div class="sessions">
                {#each report.sessions as session (session.id)}
                  <div class="session">
                    <div class="session-copy">
                      <span class="session-title">{session.title || session.id.slice(0, 8)}</span>
                      <span class="session-model">{session.model || session.source}</span>
                    </div>
                    <span class="messages">{session.messages}</span>
                    <time datetime={session.startedAt}>{shortDate(session.startedAt)}</time>
                  </div>
                {/each}
              </div>
            {:else}
              <p class="side-empty">{report.sessionsNote || "No Hermes sessions recorded."}</p>
            {/if}
          </Card>
        </aside>
      </div>
    </div>
  {/if}
</Page>

<style>
  .loading { padding: var(--s5) 0; color: var(--ink-mute); }
  .memory-sheet { display: flex; flex-direction: column; gap: var(--s5); }
  .readouts { display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); border-block: 1px solid var(--line); }
  .readout { display: flex; flex-direction: column; gap: var(--s1); min-width: 0; padding: var(--s4); }
  .readout:first-child { padding-left: 0; }
  .readout + .readout { border-left: 1px solid var(--line-soft); }
  .readout-main { display: flex; align-items: center; min-height: 30px; color: var(--ink); font-size: var(--f-value); font-weight: 500; line-height: 1.1; }
  .provider .readout-main { padding-top: var(--s1); }
  .readout-sub { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--ink-faint); font-size: var(--f-small); }
  .memory-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(300px, 340px); gap: var(--s5); align-items: start; }
  :global(.graph-card > .card-head) { padding: var(--s4) var(--s5) var(--s3); border-bottom: 1px solid var(--line-soft); }
  :global(.graph-card > .card-body) { padding: 0; }
  .graph-empty { padding: var(--s5); min-height: 420px; }
  .memory-side { display: flex; flex-direction: column; gap: var(--s4); min-width: 0; }
  .selection { display: flex; flex-direction: column; gap: var(--s2); }
  .selection-name { color: var(--ink); font-size: var(--f-row); font-weight: 500; overflow-wrap: anywhere; }
  .selection code { color: var(--ink-mute); font-size: var(--f-small); overflow-wrap: anywhere; }
  dl { display: grid; gap: var(--s2); margin: var(--s2) 0 0; }
  dl div { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s3); border-top: 1px solid var(--line-soft); padding-top: var(--s2); }
  dt { color: var(--ink-mute); font-size: var(--f-small); }
  dd { margin: 0; color: var(--ink); font-variant-numeric: tabular-nums; }
  .side-empty { color: var(--ink-mute); font-size: var(--f-small); }
  .sessions { max-height: 330px; overflow: auto; }
  .session { display: grid; grid-template-columns: minmax(0, 1fr) auto auto; gap: var(--s2); align-items: center; min-height: 44px; border-top: 1px solid var(--line-soft); }
  .session:first-child { border-top: 0; }
  .session-copy { min-width: 0; display: flex; flex-direction: column; }
  .session-title { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--ink-dim); font-size: var(--f-small); }
  .session-model, .messages { font-family: var(--mono); font-size: var(--f-tiny); color: var(--ink-faint); }
  time { color: var(--ink-faint); font-size: var(--f-small); }

  @media (max-width: 1120px) {
    .memory-grid { grid-template-columns: 1fr; }
    .memory-side { display: grid; grid-template-columns: repeat(3, minmax(0, 1fr)); }
  }
  @media (max-width: 820px) {
    .readouts { grid-template-columns: repeat(2, minmax(0, 1fr)); }
    .readout:nth-child(3) { border-left: 0; border-top: 1px solid var(--line-soft); padding-left: 0; }
    .readout:nth-child(4) { border-top: 1px solid var(--line-soft); }
    .memory-side { grid-template-columns: 1fr; }
  }
</style>
