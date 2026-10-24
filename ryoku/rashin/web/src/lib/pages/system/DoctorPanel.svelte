<script lang="ts">
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import Fold from "$lib/ui/Fold.svelte";
  import type { DoctorScan, FixRequest, FixState } from "$lib/pages/overview/types";
  import { attentionFindings } from "$lib/pages/overview/types";
  import { ago } from "./types";

  interface Props {
    scan: DoctorScan | null;
    loading: boolean;
    query: string;
    states: Record<string, FixState>;
    copied: string;
    onrefresh: () => void;
    oncopy: (key: string, text: string) => void;
    onfix: (key: string, request: FixRequest) => void;
  }

  let { scan, loading, query, states, copied, onrefresh, oncopy, onfix }: Props = $props();
  const allIssues = $derived(attentionFindings(scan));
  const issues = $derived(allIssues.filter((finding) => `${finding.name} ${finding.detail} ${finding.remedy ?? ""}`.toLowerCase().includes(query)));
  const passing = $derived((scan?.findings ?? []).filter((finding) => finding.status === "ok" || finding.status === "fixed").length);
  const notes = $derived((scan?.findings ?? []).filter((finding) => finding.status === "note"));
</script>

{#if !scan && loading}
  <p class="loading">Running Ryoku's read-only health check. This can take a few seconds…</p>
{:else if scan?.error}
  <Empty title="The health check did not answer" body={`${scan.error} Refresh to run ryoku doctor again.`} icon="warn">
    {#snippet action()}<Button icon="refresh" busy={loading} onclick={onrefresh}>Refresh</Button>{/snippet}
  </Empty>
{:else if scan}
  <header class="summary">
    <div>
      <strong>{passing} of {scan.findings?.length ?? 0} checks pass</strong>
      <span>Checked {ago(scan.collectedAt)}</span>
    </div>
    <Button icon="refresh" busy={loading} onclick={onrefresh}>{loading ? "Checking" : "Check again"}</Button>
    {#if allIssues.length}
      <Button variant="plate" icon="spark" busy={states.all?.phase === "opening"} onclick={() => onfix("all", { kind: "doctor" })}>Fix all with AI</Button>
    {/if}
  </header>

  {#if states.all && states.all.phase !== "idle" && states.all.phase !== "opening"}
    <p class="all-state" class:failed={states.all.phase === "failed"}>{states.all.message}</p>
  {/if}

  {#if issues.length}
    <div class="findings">
      {#each issues as finding (finding.name)}
        {@const key = `doctor:${finding.name}`}
        {@const state = states[key] ?? { phase: "idle" }}
        <article class:urgent={finding.status === "fail"}>
          <div class="finding-head">
            <Chip tone={finding.status === "fail" ? "alert" : finding.status === "warn" ? "quiet" : "line"}>{finding.status === "todo" ? "Doctor can fix" : finding.status}</Chip>
            <h3>{finding.name}</h3>
          </div>
          <p>{finding.detail}</p>
          {#if finding.remedy}
            <div class="remedy">
              <span>Proposed remedy</span>
              <code>{finding.remedy}</code>
              <Button size="sm" variant="quiet" icon={copied === key ? "check" : "copy"} onclick={() => oncopy(key, finding.remedy ?? "")}>{copied === key ? "Copied" : "Copy"}</Button>
            </div>
          {/if}
          <div class="actions">
            <Button variant="plate" icon="spark" busy={state.phase === "opening"} onclick={() => onfix(key, { kind: "doctor", name: finding.name })}>{state.phase === "opening" ? "Opening the agent" : "Fix with AI"}</Button>
            {#if state.phase !== "idle" && state.phase !== "opening"}<span class:failed={state.phase === "failed"}>{state.message}</span>{/if}
          </div>
        </article>
      {/each}
    </div>
  {:else}
    <Empty title={query ? "Nothing matches" : "Every check passes"} body={query ? "Clear the filter to see the remaining findings." : "Ryoku doctor found nothing that needs a person or an agent."} icon="check" />
  {/if}

  {#if notes.length}
    <div class="notes">
      <Fold>
        {#snippet summary()}<span>{notes.length} advisory {notes.length === 1 ? "note" : "notes"}</span>{/snippet}
        <div class="note-list">
          {#each notes as note (note.name)}<p><strong>{note.name}</strong> {note.detail}</p>{/each}
        </div>
      </Fold>
    </div>
  {/if}
{:else}
  <Empty title="The health check has not run" body="Refresh to ask Ryoku doctor for a read-only report." icon="shield">
    {#snippet action()}<Button icon="refresh" onclick={onrefresh}>Refresh</Button>{/snippet}
  </Empty>
{/if}

<style>
  .loading { color: var(--ink-mute); }
  .summary { display: flex; align-items: center; gap: var(--s2); margin-bottom: var(--s4); padding: var(--s3) var(--s4); border: 1px solid var(--line-soft); border-radius: var(--radius); }
  .summary > div { display: flex; flex: 1; flex-direction: column; gap: var(--s1); }
  .summary strong { color: var(--ink); font-size: var(--f-body); font-weight: 500; }
  .summary span { color: var(--ink-faint); font-size: var(--f-small); }
  .all-state { margin: calc(var(--s2) * -1) 0 var(--s4); color: var(--ink-mute); font-size: var(--f-small); }
  .all-state.failed { color: var(--alert); }
  .findings { display: flex; flex-direction: column; gap: var(--s2); }
  article { padding: var(--s4) var(--s5); border: 1px solid var(--line-soft); border-radius: var(--radius); }
  article.urgent { border-left-color: var(--alert); }
  .finding-head { display: flex; align-items: center; gap: var(--s3); }
  h3 { color: var(--ink); font-size: var(--f-row); font-weight: 500; }
  article > p { margin-top: var(--s2); max-width: 80ch; color: var(--ink-mute); font-size: var(--f-small); }
  .remedy { display: grid; grid-template-columns: minmax(0, 1fr) auto; align-items: center; gap: var(--s2); max-width: 80ch; margin-top: var(--s3); padding: var(--s3); border: 1px solid var(--line-soft); border-radius: var(--radius); background: var(--tint5); }
  .remedy > span { grid-column: 1 / -1; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); letter-spacing: var(--track-label); text-transform: uppercase; }
  .remedy code { color: var(--ink-dim); font-size: var(--f-micro); overflow-wrap: anywhere; }
  .actions { display: flex; align-items: center; gap: var(--s3); margin-top: var(--s3); }
  .actions span { color: var(--ink-mute); font-size: var(--f-small); }
  .actions span.failed { color: var(--alert); }
  .notes { margin-top: var(--s4); }
  .note-list { padding: var(--s2) 0 var(--s2) var(--s5); }
  .note-list p { margin-top: var(--s2); color: var(--ink-mute); font-size: var(--f-small); }
  .note-list strong { color: var(--ink); font-weight: 500; }
  @media (max-width: 700px) { .summary { align-items: stretch; flex-direction: column; } }
</style>
