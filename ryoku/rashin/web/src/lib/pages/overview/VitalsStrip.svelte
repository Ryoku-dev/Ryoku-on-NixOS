<script lang="ts">
  import type { Vitals } from "./types";
  import { formatBytes, percent } from "./types";
  import type { SystemInventory } from "$lib/pages/system/types";

  interface Props {
    vitals: Vitals | null;
    system: SystemInventory | null;
  }

  let { vitals, system }: Props = $props();
  const memoryPct = $derived(vitals ? percent(vitals.mem.used, vitals.mem.total) : 0);
  const actTips = $derived(system?.tips.filter((tip) => tip.severity === "act").length ?? 0);
</script>

<section class="strip" aria-label="Live machine vitals">
  <div class="live-key">
    <span class="pulse" aria-hidden="true"></span>
    <span class="t-label">Live</span>
  </div>

  <div class="kpi">
    <div class="kpi-head"><span class="t-label">CPU</span><strong class="t-value">{vitals ? Math.round(vitals.cpu.percent) : "—"}<small>{vitals ? "%" : ""}</small></strong></div>
    <div class="bar" class:alert={(vitals?.cpu.percent ?? 0) >= 90}><i style:width={`${Math.min(100, vitals?.cpu.percent ?? 0)}%`}></i></div>
    <p>{vitals?.cpu.model || "Waiting for CPU"}{#if vitals} · {vitals.cpu.cores} cores{/if}</p>
  </div>

  <div class="kpi">
    <div class="kpi-head"><span class="t-label">Memory</span><strong class="t-value">{vitals ? Math.round(memoryPct) : "—"}<small>{vitals ? "%" : ""}</small></strong></div>
    <div class="bar" class:alert={memoryPct >= 90}><i style:width={`${memoryPct}%`}></i></div>
    <p>{vitals ? `${formatBytes(vitals.mem.used)} / ${formatBytes(vitals.mem.total)}` : "Waiting for memory"}</p>
  </div>

  {#each vitals?.disks ?? [] as disk (disk.mount)}
    {@const diskPct = percent(disk.used, disk.total)}
    <div class="kpi">
      <div class="kpi-head"><span class="t-label">Disk {disk.mount}</span><strong class="t-value">{Math.round(diskPct)}<small>%</small></strong></div>
      <div class="bar" class:alert={diskPct >= 90}><i style:width={`${diskPct}%`}></i></div>
      <p>{formatBytes(disk.total - disk.used)} free · {formatBytes(disk.total)}</p>
    </div>
  {/each}

  <div class="kpi">
    <div class="kpi-head"><span class="t-label">GPU</span><strong class="t-value">{vitals?.gpu ? vitals.gpu.percent : "—"}<small>{vitals?.gpu ? "%" : ""}</small></strong></div>
    <div class="bar" class:alert={(vitals?.gpu?.percent ?? 0) >= 90}><i style:width={`${vitals?.gpu?.percent ?? 0}%`}></i></div>
    <p>{#if vitals?.gpu}{vitals.gpu.name} · {formatBytes(vitals.gpu.vramUsed)} / {formatBytes(vitals.gpu.vramTotal ?? 0)} VRAM{:else}Runtime-suspended{/if}</p>
  </div>

  {#if system}
    <div class="system-pulse" aria-label="System inventory summary">
      <div><span>Services</span><strong>{system.services.runningN}/{system.services.totalN}</strong></div>
      <div><span>Timers</span><strong>{system.timers.active.length}{#if system.timers.passive.length}<small> +{system.timers.passive.length} idle</small>{/if}</strong></div>
      <div><span>Containers</span><strong>{system.containers.runningN}/{system.containers.totalN}</strong></div>
      <div><span>Listeners</span><strong>{system.listeners.rows.length}</strong></div>
      <div><span>Attention</span><strong class:attention={actTips > 0}>{actTips ? `${actTips} act · ${system.tips.length}` : system.tips.length}</strong></div>
    </div>
  {/if}
</section>

<style>
  .strip {
    display: flex;
    flex-wrap: wrap;
    align-items: stretch;
    border-bottom: 1px solid var(--line-soft);
    background: var(--paper);
  }
  .live-key { display: flex; align-items: center; gap: var(--s2); padding: var(--s5); border-right: 1px solid var(--line-soft); }
  .pulse { width: 7px; height: 7px; border-radius: 50%; background: var(--bone); animation: live-pulse 2s var(--ease) infinite; }
  @keyframes live-pulse { 50% { opacity: .34; } }
  .kpi { flex: 1 1 190px; min-width: 0; padding: var(--s4) var(--s5); border-right: 1px solid var(--line-soft); }
  .kpi-head { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s3); }
  .kpi .t-value { font-size: 22px; }
  .kpi .t-value small { font-size: var(--f-small); color: var(--ink-mute); font-weight: 400; }
  .kpi .bar { margin-top: var(--s2); }
  .kpi p { margin-top: var(--s2); max-width: 34ch; color: var(--ink-mute); font-size: var(--f-micro); white-space: nowrap; overflow: hidden; text-overflow: ellipsis; }
  .system-pulse {
    flex: 1 0 100%;
    display: grid;
    grid-template-columns: repeat(5, minmax(0, 1fr));
    border-top: 1px solid var(--line-soft);
  }
  .system-pulse div { display: flex; align-items: baseline; justify-content: space-between; gap: var(--s3); padding: var(--s2) var(--s5); border-right: 1px solid var(--line-soft); }
  .system-pulse div:last-child { border-right: 0; }
  .system-pulse span { color: var(--ink-mute); font-size: var(--f-small); }
  .system-pulse strong { color: var(--ink); font-size: var(--f-small); font-weight: 500; font-variant-numeric: tabular-nums; }
  .system-pulse small { color: var(--ink-faint); font-size: var(--f-micro); font-weight: 400; }
  .system-pulse .attention { color: var(--alert); }
  @media (max-width: 900px) {
    .live-key { flex: 1 0 100%; border-right: 0; border-bottom: 1px solid var(--line-soft); padding: var(--s3) var(--s5); }
    .system-pulse { grid-template-columns: repeat(2, 1fr); }
  }
  @media (max-width: 560px) {
    .strip { display: block; }
    .kpi { border-right: 0; border-bottom: 1px solid var(--line-soft); }
    .system-pulse { grid-template-columns: 1fr; }
  }
</style>
