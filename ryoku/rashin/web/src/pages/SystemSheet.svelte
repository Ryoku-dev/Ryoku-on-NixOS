<script lang="ts">
  import { onMount } from "svelte";
  import Page from "$lib/app/Page.svelte";
  import { api, type Json } from "$lib/api/client";
  import { router } from "$lib/app/router.svelte";
  import Button from "$lib/ui/Button.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import Field from "$lib/ui/Field.svelte";
  import InventoryTabs from "$lib/pages/system/InventoryTabs.svelte";
  import type { SystemInventory } from "$lib/pages/system/types";
  import { ago, normalizeInventory } from "$lib/pages/system/types";
  import type { DoctorScan, FixAnswer, FixRequest, FixState } from "$lib/pages/overview/types";
  import { attentionFindings } from "$lib/pages/overview/types";

  const TAB_NAMES = ["services", "timers", "schedules", "containers", "listeners", "processes", "mounts", "doctor", "tips"];

  let inventory = $state<SystemInventory | null>(null);
  let loading = $state(true);
  let error = $state("");
  let doctor = $state<DoctorScan | null>(null);
  let doctorLoading = $state(true);
  const requestedTab = router.rest[0];
  let active = $state(requestedTab && TAB_NAMES.includes(requestedTab) ? requestedTab : "services");
  let serviceSub = $state("running");
  let query = $state("");
  let fixStates = $state<Record<string, FixState>>({});
  let copied = $state("");

  const searchQuery = $derived(query.trim().toLowerCase());
  const actTips = $derived(inventory?.tips.filter((tip) => tip.severity === "act").length ?? 0);
  const doctorIssues = $derived(attentionFindings(doctor).length);

  async function loadInventory(quiet = false): Promise<void> {
    if (!quiet) loading = true;
    try {
      inventory = normalizeInventory((await api.system()) as unknown as SystemInventory);
      error = "";
    } catch (caught) {
      if (!quiet || !inventory) error = caught instanceof Error ? caught.message : "The daemon is not answering.";
    } finally {
      loading = false;
    }
  }

  async function loadDoctor(refresh = false): Promise<void> {
    doctorLoading = true;
    try {
      doctor = (await api.doctor(refresh)) as unknown as DoctorScan;
    } catch (caught) {
      doctor = {
        findings: [],
        collectedAt: new Date().toISOString(),
        error: caught instanceof Error ? caught.message : "The daemon is not answering.",
      };
    } finally {
      doctorLoading = false;
    }
  }

  async function runFix(key: string, request: FixRequest): Promise<void> {
    fixStates = { ...fixStates, [key]: { phase: "opening", message: "Opening the agent" } };
    try {
      const answer = (await api.fix(request as unknown as Json)) as unknown as FixAnswer;
      const where = answer.harness ? ` with ${answer.harness}` : "";
      fixStates = { ...fixStates, [key]: { phase: "opened", message: `Opened in a terminal${where}` } };
    } catch (caught) {
      fixStates = {
        ...fixStates,
        [key]: { phase: "failed", message: caught instanceof Error ? caught.message : "The agent could not be opened." },
      };
    }
  }

  async function copyText(key: string, text: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(text);
      copied = key;
      window.setTimeout(() => {
        if (copied === key) copied = "";
      }, 1200);
    } catch {
      copied = "";
    }
  }

  function selectTab(value: string): void {
    active = value;
    query = "";
    router.go("system", value);
    if (value === "doctor" && !doctor) void loadDoctor();
  }

  onMount(() => {
    void loadInventory();
    void loadDoctor();
    const timer = window.setInterval(() => {
      if (!document.hidden) void loadInventory(true);
    }, 30000);
    return () => clearInterval(timer);
  });
</script>

<Page
  title="System"
  gloss="演算"
  lead="Every unit, timer, socket and disk on this box. This sheet only reads; Rashin never executes a tip."
>
  {#snippet tools()}
    <Chip tone={actTips ? "alert" : "line"}>{actTips ? `${actTips} need action` : "0 urgent tips"}</Chip>
    {#if doctorIssues}<Chip tone="quiet">{doctorIssues} doctor {doctorIssues === 1 ? "finding" : "findings"}</Chip>{/if}
  {/snippet}

  <div class="toolbar">
    <Field label="Filter active tab" placeholder="Unit, command, process or path" bind:value={query} autocomplete="off" />
    <span class="stamp" class:stale={!!inventory && Date.now() - new Date(inventory.collectedAt).getTime() > 120000}>{inventory ? `Updated ${ago(inventory.collectedAt)}` : "Waiting for inventory"}</span>
    <Button icon="refresh" busy={loading} onclick={() => active === "doctor" ? void loadDoctor(true) : void loadInventory()}>Rescan</Button>
  </div>

  {#if loading && !inventory}
    <p class="reading">Reading services, schedules, sockets and storage…</p>
  {:else if error && !inventory}
    <Empty title="The machine inventory did not answer" body={`${error} Check that the preview daemon is running, then rescan.`} icon="warn">
      {#snippet action()}<Button icon="refresh" onclick={() => void loadInventory()}>Rescan</Button>{/snippet}
    </Empty>
  {:else if inventory}
    <InventoryTabs
      {inventory}
      {doctor}
      {doctorLoading}
      {active}
      {serviceSub}
      query={searchQuery}
      states={fixStates}
      {copied}
      onactive={selectTab}
      onserviceSub={(value) => (serviceSub = value)}
      ondoctorRefresh={() => void loadDoctor(true)}
      oncopy={(key, text) => void copyText(key, text)}
      onfix={(key, request) => void runFix(key, request)}
    />
  {/if}
</Page>

<style>
  .toolbar { display: grid; grid-template-columns: minmax(220px, 340px) 1fr auto; align-items: end; gap: var(--s3); margin-bottom: var(--s5); }
  .stamp { justify-self: end; align-self: center; color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-micro); letter-spacing: .06em; }
  .stamp.stale { color: var(--alert); }
  .reading { color: var(--ink-mute); }
  @media (max-width: 720px) {
    .toolbar { grid-template-columns: 1fr auto; }
    .stamp { grid-column: 1 / -1; grid-row: 2; justify-self: start; }
  }
</style>
