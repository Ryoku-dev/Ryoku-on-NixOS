<script lang="ts">
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import type { DoctorFinding, DoctorScan, FixRequest, FixState } from "./types";

  interface Props {
    scan: DoctorScan | null;
    issues: DoctorFinding[];
    loading: boolean;
    states: Record<string, FixState>;
    copied: string;
    onrefresh: () => void;
    onfix: (key: string, request: FixRequest) => void;
    oncopy: (key: string, text: string) => void;
    onopenDoctor: () => void;
  }

  let { scan, issues, loading, states, copied, onrefresh, onfix, oncopy, onopenDoctor }: Props = $props();
  const passing = $derived((scan?.findings ?? []).filter((finding) => finding.status === "ok" || finding.status === "fixed").length);
</script>

{#if scan?.error}
  <section class="health-error" aria-live="polite">
    <div><strong>Health check unavailable</strong><p>{scan.error}</p></div>
    <Button size="sm" icon="refresh" busy={loading} onclick={onrefresh}>Refresh</Button>
  </section>
{:else if issues.length}
  <section class="health-band" aria-label="Health findings">
    <header>
      <span class="seal t-jp" aria-hidden="true">力</span>
      <div>
        <h2>{issues.length === 1 ? "One thing needs a decision" : `${issues.length} things need a decision`}</h2>
        <p>{passing} of {scan?.findings?.length ?? issues.length} checks pass. Rashin only hands a finding to your terminal agent when you ask.</p>
      </div>
      <div class="head-actions">
        <Button size="sm" variant="quiet" onclick={onopenDoctor}>Open Doctor</Button>
        <Button size="sm" icon="refresh" busy={loading} onclick={onrefresh}>Refresh</Button>
        <Button
          size="sm"
          variant="plate"
          icon="spark"
          busy={states.all?.phase === "opening"}
          onclick={() => onfix("all", { kind: "doctor" })}
        >Fix all with AI</Button>
      </div>
    </header>

    <div class="findings">
      {#each issues as finding (finding.name)}
        {@const state = states[finding.name] ?? { phase: "idle" }}
        <article>
          <div class="finding-head">
            <Chip tone={finding.status === "fail" ? "alert" : "quiet"}>{finding.status === "todo" ? "Doctor can fix" : finding.status}</Chip>
            <h3>{finding.name}</h3>
          </div>
          <p>{finding.detail}</p>
          {#if finding.remedy}
            <div class="remedy">
              <span>Proposed remedy</span>
              <code>{finding.remedy}</code>
              <Button size="sm" variant="quiet" icon={copied === finding.name ? "check" : "copy"} onclick={() => oncopy(finding.name, finding.remedy ?? "")}>{copied === finding.name ? "Copied" : "Copy"}</Button>
            </div>
          {/if}
          <div class="finding-actions">
            <Button
              size="sm"
              variant="line"
              icon="spark"
              busy={state.phase === "opening"}
              onclick={() => onfix(finding.name, { kind: "doctor", name: finding.name })}
            >{state.phase === "opening" ? "Opening the agent" : "Fix with AI"}</Button>
            {#if state.phase !== "idle" && state.phase !== "opening"}<span class:failed={state.phase === "failed"}>{state.message}</span>{/if}
          </div>
        </article>
      {/each}
    </div>
    {#if states.all && states.all.phase !== "idle" && states.all.phase !== "opening"}
      <p class="all-state" class:failed={states.all.phase === "failed"}>{states.all.message}</p>
    {/if}
  </section>
{/if}

<style>
  .health-error, .health-band { border: 1px solid var(--line); border-radius: var(--radius); }
  .health-error { display: flex; align-items: center; justify-content: space-between; gap: var(--s4); padding: var(--s4) var(--s5); }
  .health-error strong { color: var(--ink); font-weight: 500; }
  .health-error p { margin-top: var(--s1); color: var(--ink-mute); font-size: var(--f-small); }
  .health-band { position: relative; overflow: hidden; }
  .health-band::before { content: ""; position: absolute; inset: 0 auto 0 0; width: 2px; background: var(--alert); }
  header { display: grid; grid-template-columns: auto minmax(220px, 1fr) auto; align-items: center; gap: var(--s4); padding: var(--s4) var(--s5); border-bottom: 1px solid var(--line-soft); }
  .seal { color: var(--alert); font-size: 17px; font-weight: 700; }
  h2 { color: var(--ink); font-size: var(--f-row); font-weight: 500; }
  header p { margin-top: var(--s1); color: var(--ink-mute); font-size: var(--f-small); }
  .head-actions { display: flex; align-items: center; gap: var(--s2); }
  .findings { display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 330px), 1fr)); }
  article { padding: var(--s4) var(--s5); border-right: 1px solid var(--line-soft); border-bottom: 1px solid var(--line-soft); }
  .finding-head { display: flex; align-items: center; gap: var(--s3); }
  h3 { color: var(--ink); font-size: var(--f-body); font-weight: 500; }
  article > p { margin-top: var(--s2); color: var(--ink-mute); font-size: var(--f-small); }
  .remedy { display: grid; grid-template-columns: 1fr auto; align-items: center; gap: var(--s2); margin-top: var(--s3); padding: var(--s3); border: 1px solid var(--line-soft); border-radius: var(--radius); background: var(--tint5); }
  .remedy > span { grid-column: 1 / -1; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); letter-spacing: var(--track-label); text-transform: uppercase; }
  .remedy code { color: var(--ink-dim); font-size: var(--f-micro); overflow-wrap: anywhere; }
  .finding-actions { display: flex; align-items: center; gap: var(--s3); margin-top: var(--s3); }
  .finding-actions span, .all-state { color: var(--ink-mute); font-size: var(--f-small); }
  .finding-actions .failed, .all-state.failed { color: var(--alert); }
  .all-state { padding: var(--s3) var(--s5); border-top: 1px solid var(--line-soft); }
  @media (max-width: 980px) {
    header { grid-template-columns: auto 1fr; }
    .head-actions { grid-column: 2; flex-wrap: wrap; }
  }
  @media (max-width: 620px) {
    header { grid-template-columns: 1fr; }
    .seal { display: none; }
    .head-actions { grid-column: auto; }
  }
</style>
