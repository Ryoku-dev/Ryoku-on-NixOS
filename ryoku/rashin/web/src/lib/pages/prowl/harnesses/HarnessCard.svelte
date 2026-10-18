<script lang="ts">
  import Button from "$lib/ui/Button.svelte";
  import Card from "$lib/ui/Card.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Dialog from "$lib/ui/Dialog.svelte";
  import Switch from "$lib/ui/Switch.svelte";
  import type { MergedHarness } from "./harnesses";
  import { skillsActionable, stateLabel } from "./harnesses";

  interface Props {
    harness: MergedHarness;
    busy?: string;
    onconnect: (id: string) => void;
    ondisconnect: (id: string) => void;
    ondefault: (id: string, prowl: boolean) => void;
    onskills: (id: string) => void;
  }

  let { harness, busy = "", onconnect, ondisconnect, ondefault, onskills }: Props = $props();
  let disconnectOpen = $state(false);
  const connected = $derived(harness.connected || harness.injected || harness.active);
  const stateTone = $derived(harness.credentialStale ? "alert" : harness.active ? "plate" : connected ? "line" : "quiet");
  const skillLabel = $derived.by(() => {
    switch (harness.skills) {
      case "current": return "Skills current";
      case "install": return "Skills not installed";
      case "update": return "Skills need update";
      case "conflict": return "Skills have conflicts";
      case "error": return "Skills check failed";
      case "unsupported": return "Skills unsupported";
    }
  });
</script>

<Card class="harness-card">
  <div class="harness-head">
    <div>
      <div class="title-line">
        <h2>{harness.name}</h2>
        <Chip tone={harness.installed ? "line" : "quiet"}>{harness.installed ? "Detected" : "Not installed"}</Chip>
      </div>
      {#if harness.version}<code>{harness.version}</code>{/if}
    </div>
    <Chip tone={stateTone}>{harness.credentialStale ? "Credential stale" : stateLabel(harness.state)}</Chip>
  </div>

  {#if harness.reason}
    <p class:pending={harness.pending} class="reason">
      {harness.reason}
      {#if harness.pending}<a href="#/prowl/providers">Open Providers</a>{/if}
    </p>
  {/if}

  <dl class="facts">
    <div><dt>Prowl plug-in</dt><dd>{connected ? "Connected" : "Not connected"}</dd></div>
    <div><dt>Model default</dt><dd>{harness.active ? "Prowl auto" : "Harness choice"}</dd></div>
    <div><dt>Rashin wiring</dt><dd>{harness.rashinWired ? "Connected" : "Not connected"}</dd></div>
    <div><dt>Skills</dt><dd>{skillLabel}{harness.skillCount ? ` · ${harness.skillCount} found` : ""}</dd></div>
    {#if harness.model || harness.provider}<div><dt>Current model</dt><dd>{[harness.model, harness.provider].filter(Boolean).join(" / ")}</dd></div>{/if}
  </dl>

  {#if harness.files.length}
    <div class="files">
      <span class="t-label">Prowl-managed files</span>
      {#each harness.files as file (file)}<code title={file}>{file}</code>{/each}
    </div>
  {/if}
  {#if connected && harness.routingSupported}
    <div class="default-row">
      <div>
        <strong>Default to Prowl auto</strong>
        <p>Prowl stays available either way. This changes only the harness default, never your explicit model pick.</p>
      </div>
      <Switch
        checked={harness.active}
        label={`Default ${harness.name} to Prowl auto`}
        disabled={Boolean(busy)}
        onchange={(checked) => ondefault(harness.id, checked)}
      />
    </div>
  {/if}


  {#if harness.installed}
    <div class="actions">
      {#if connected}
        <Button size="sm" busy={busy === "disconnect"} onclick={() => (disconnectOpen = true)}>Disconnect</Button>
      {:else if harness.routingSupported}
        <Button variant="plate" size="sm" busy={busy === "connect"} onclick={() => onconnect(harness.id)}>Connect</Button>
      {/if}
      {#if skillsActionable(harness.skills)}
        <Button variant="quiet" size="sm" busy={busy === "skills"} onclick={() => onskills(harness.id)}>Install skills</Button>
      {/if}
    </div>
  {/if}
</Card>

<Dialog
  bind:open={disconnectOpen}
  title={`Disconnect ${harness.name}?`}
  description="Prowl removes only its managed configuration. Harness settings changed since connection stay untouched."
>
  <p class="confirm-copy">The harness keeps its own model choice after Prowl is removed.</p>
  {#snippet footer()}
    <Button variant="quiet" onclick={() => (disconnectOpen = false)}>Keep connected</Button>
    <Button variant="plate" autofocus busy={busy === "disconnect"} onclick={() => { disconnectOpen = false; ondisconnect(harness.id); }}>Disconnect</Button>
  {/snippet}
</Dialog>

<style>
  .harness-head { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--s3); }
  .title-line { display: flex; align-items: center; flex-wrap: wrap; gap: var(--s2); }
  h2 { color: var(--ink); font-size: var(--f-row); font-weight: 500; }
  .harness-head code { display: block; margin-top: var(--s1); color: var(--ink-mute); font-size: var(--f-micro); }
  .reason { margin-top: var(--s3); padding: var(--s2) var(--s3); border-left: 1px solid var(--line-strong); color: var(--ink-mute); font-size: var(--f-small); }
  .reason.pending { border-left-color: var(--alert); }
  .reason a { margin-left: var(--s2); color: var(--ink); text-decoration: underline; text-underline-offset: 3px; }
  .facts { display: grid; gap: var(--s2); margin-top: var(--s4); padding-block: var(--s3); border-block: 1px solid var(--line-soft); }
  .facts div { display: grid; grid-template-columns: 120px minmax(0, 1fr); gap: var(--s3); align-items: baseline; }
  dt, .files > span { color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); letter-spacing: var(--track-label); text-transform: uppercase; }
  dd { color: var(--ink-dim); font-size: var(--f-small); }
  .default-row { display: flex; align-items: center; justify-content: space-between; gap: var(--s4); padding: var(--s3) 0; border-top: 1px solid var(--line-soft); }
  .default-row strong { color: var(--ink); font-size: var(--f-small); font-weight: 500; }
  .default-row p { margin-top: var(--s1); color: var(--ink-faint); font-size: var(--f-micro); line-height: 1.4; }
  .files { display: grid; gap: var(--s1); margin-top: var(--s3); }
  .files code { overflow: hidden; color: var(--ink-mute); font-size: var(--f-micro); text-overflow: ellipsis; white-space: nowrap; }
  .actions { display: flex; justify-content: flex-end; flex-wrap: wrap; gap: var(--s2); margin-top: var(--s4); }
  .confirm-copy { color: var(--ink-dim); font-size: var(--f-small); }
  @media (max-width: 520px) { .facts div { grid-template-columns: 1fr; gap: var(--s1); } }
</style>
