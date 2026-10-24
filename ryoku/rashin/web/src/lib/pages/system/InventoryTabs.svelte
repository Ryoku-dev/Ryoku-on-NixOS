<script lang="ts">
  import Tabs from "$lib/ui/Tabs.svelte";
  import Seg from "$lib/ui/Seg.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import DoctorPanel from "./DoctorPanel.svelte";
  import TipsPanel from "./TipsPanel.svelte";
  import type { DoctorScan, FixRequest, FixState } from "$lib/pages/overview/types";
  import { attentionFindings } from "$lib/pages/overview/types";
  import type { CronEntry, SystemInventory } from "./types";
  import { humanBytes, isWildAddress, shortDate } from "./types";

  interface ScheduleRow extends CronEntry { kind: string; }

  interface Props {
    inventory: SystemInventory;
    doctor: DoctorScan | null;
    doctorLoading: boolean;
    active: string;
    serviceSub: string;
    query: string;
    states: Record<string, FixState>;
    copied: string;
    onactive: (value: string) => void;
    onserviceSub: (value: string) => void;
    ondoctorRefresh: () => void;
    oncopy: (key: string, text: string) => void;
    onfix: (key: string, request: FixRequest) => void;
  }

  let {
    inventory,
    doctor,
    doctorLoading,
    active,
    serviceSub,
    query,
    states,
    copied,
    onactive,
    onserviceSub,
    ondoctorRefresh,
    oncopy,
    onfix,
  }: Props = $props();

  const serviceOptions = $derived([
    { value: "running", label: `Running ${inventory.services.running.length}` },
    { value: "stopped", label: `Stopped ${inventory.services.stopped.length}` },
    { value: "user", label: `User ${inventory.services.userOnly.length}` },
  ]);
  const serviceRows = $derived(serviceSub === "running" ? inventory.services.running : serviceSub === "stopped" ? inventory.services.stopped : inventory.services.userOnly);
  const filteredServices = $derived(serviceRows.filter((row) => matches([row.name, row.activeState, row.subState ?? "", row.description ?? ""], query)));
  const timers = $derived([...inventory.timers.active, ...inventory.timers.passive]);
  const filteredTimers = $derived(timers.filter((row) => matches([row.unit, row.activates ?? "", row.nextRun, row.left ?? ""], query)));
  const schedules = $derived<ScheduleRow[]>([
    ...inventory.schedules.crontabs.map((row) => ({ ...row, kind: "cron" })),
    ...inventory.schedules.anacron.map((row) => ({ ...row, kind: "periodic" })),
    ...inventory.schedules.atJobs.map((row) => ({ ...row, kind: "one-shot" })),
  ]);
  const filteredSchedules = $derived(schedules.filter((row) => matches([row.schedule, row.command, row.origin, row.kind], query)));
  const containers = $derived(inventory.containers.rows.filter((row) => matches([row.name, row.image, row.state, row.status], query)));
  const listeners = $derived([...inventory.listeners.rows]
    .sort((a, b) => (a.loopback ? 2 : isWildAddress(a.address) ? 1 : 0) - (b.loopback ? 2 : isWildAddress(b.address) ? 1 : 0) || a.port - b.port)
    .filter((row) => matches([row.proto, row.address, String(row.port), row.process ?? ""], query)));
  const processes = $derived(inventory.processes.rows.filter((row) => matches([row.command, String(row.pid)], query)));
  const mounts = $derived(inventory.mounts.rows.filter((row) => matches([row.mountpoint, row.fstype, row.device], query)));
  const tips = $derived(inventory.tips.filter((tip) => matches([tip.title, tip.detail, tip.command ?? "", tip.severity], query)));
  const doctorCount = $derived(attentionFindings(doctor).length);
  const actTips = $derived(inventory.tips.filter((tip) => tip.severity === "act").length);
  const tabs = $derived([
    { value: "services", label: "Services", count: inventory.services.runningN },
    { value: "timers", label: "Timers", count: timers.length },
    { value: "schedules", label: "Schedule", count: schedules.length },
    { value: "containers", label: "Containers", count: inventory.containers.totalN },
    { value: "listeners", label: "Network", count: inventory.listeners.rows.length },
    { value: "processes", label: "Processes", count: inventory.processes.rows.length },
    { value: "mounts", label: "Storage", count: inventory.mounts.rows.length },
    { value: "doctor", label: "Doctor", count: doctorCount },
    { value: "tips", label: "Tips", count: actTips },
  ]);

  function matches(cells: Array<string | number>, needle: string): boolean {
    return !needle || cells.join(" ").toLowerCase().includes(needle);
  }
</script>

<Tabs {tabs} value={active} onchange={onactive}>
  {#snippet children(tab)}
    {#if tab === "services"}
      <div class="subnav"><Seg options={serviceOptions} value={serviceSub} onchange={onserviceSub} size="sm" label="Service state" /></div>
      {#if inventory.services.note && serviceSub !== "running"}<p class="section-note">{inventory.services.note}</p>{/if}
      {#if filteredServices.length}
        <div class="table-wrap"><table class="data"><thead><tr><th>Unit</th><th>State</th><th>Detail</th></tr></thead><tbody>
          {#each filteredServices as row (row.name)}<tr><td class="mono ink">{row.name}</td><td><Chip tone={row.activeState === "failed" ? "alert" : row.activeState === "active" && row.subState === "running" ? "plate" : "quiet"}>{row.activeState === "active" && row.subState === "running" ? "running" : row.activeState}</Chip></td><td>{row.description || "—"}</td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No services in this group"} body={query ? "Clear the filter or search a different unit name." : "Choose another service state."} icon="cpu" />{/if}
    {:else if tab === "timers"}
      {#if filteredTimers.length}
        <div class="table-wrap"><table class="data"><thead><tr><th>Timer</th><th>Next</th><th>Fires</th></tr></thead><tbody>
          {#each filteredTimers as row (row.unit)}<tr><td class="mono ink">{row.unit}</td><td>{#if row.passive}<Chip tone="quiet">dormant</Chip>{:else}{row.left || shortDate(row.nextRun)}{#if row.left}<span class="dim"> {shortDate(row.nextRun)}</span>{/if}{/if}</td><td class="mono">{row.activates || "—"}</td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No timers found"} body={query ? "Clear the filter to see every timer." : "systemd reported no firing or dormant timers."} icon="history" />{/if}
    {:else if tab === "schedules"}
      {#if inventory.schedules.cronActive === false}<p class="section-note alert">The cron daemon is stopped.</p>{/if}
      {#if inventory.schedules.note}<p class="section-note">{inventory.schedules.note}</p>{/if}
      {#if filteredSchedules.length}
        <div class="table-wrap"><table class="data"><thead><tr><th>Schedule</th><th>Command</th><th>Kind</th><th>Source</th></tr></thead><tbody>
          {#each filteredSchedules as row (`${row.origin}:${row.schedule}:${row.command}`)}<tr><td class="mono ink">{row.schedule}</td><td class="mono command-cell" title={row.command}>{row.command}</td><td><Chip>{row.kind}</Chip></td><td>{row.origin}</td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No scheduled commands"} body={query ? "Clear the filter to see all schedules." : "No cron, anacron or at jobs were found."} icon="history" />{/if}
    {:else if tab === "containers"}
      {#if !inventory.containers.installed}
        <Empty title="Docker is not installed" body={inventory.containers.note || "Install Docker before container inventory can appear."} icon="grid" />
      {:else if containers.length}
        <div class="table-wrap"><table class="data"><thead><tr><th>Name</th><th>State</th><th>Image</th><th>Status</th><th>Created</th></tr></thead><tbody>
          {#each containers as row (row.id)}<tr><td class="mono ink">{row.name}</td><td><Chip tone={row.state === "running" ? "plate" : "quiet"}>{row.state === "running" ? "up" : row.state}</Chip></td><td class="mono command-cell" title={row.image}>{row.image}</td><td>{row.status}</td><td>{row.created}</td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No containers"} body={query ? "Clear the filter to see every container." : "Docker has no running or stopped containers."} icon="grid" />{/if}
    {:else if tab === "listeners"}
      {#if listeners.length}
        <div class="table-wrap"><table class="data"><thead><tr><th>Proto</th><th>Address</th><th>Reach</th><th>Process</th></tr></thead><tbody>
          {#each listeners as row (`${row.proto}:${row.address}:${row.port}:${row.process ?? ""}`)}<tr><td><Chip>{row.proto}</Chip></td><td class="mono ink">{row.address}:{row.port}</td><td><Chip tone={!row.loopback && !isWildAddress(row.address) ? "alert" : row.loopback ? "plate" : "quiet"}>{row.loopback ? "loopback" : isWildAddress(row.address) ? "all interfaces" : row.address}</Chip></td><td class="mono">{row.process || "—"}</td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No listening sockets"} body={query ? "Clear the filter to see every listener." : "No TCP or UDP listeners were reported."} icon="link" />{/if}
    {:else if tab === "processes"}
      {#if processes.length}
        <div class="table-wrap"><table class="data"><thead><tr><th class="r">CPU %</th><th class="r">PID</th><th>Command</th><th class="r">RSS</th></tr></thead><tbody>
          {#each processes as row (row.pid)}<tr><td class="r mono ink">{row.cpuPct.toFixed(1)}</td><td class="r mono">{row.pid}</td><td class="mono ink">{row.command}</td><td class="r mono">{humanBytes(row.memRss)}</td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No process snapshot"} body={query ? "Clear the filter to see top processes." : "The process collector returned no rows."} icon="cpu" />{/if}
    {:else if tab === "mounts"}
      {#if mounts.length}
        <div class="table-wrap"><table class="data"><thead><tr><th>Mount</th><th>FS</th><th class="r">Size</th><th class="r">Used</th><th class="r">Use</th></tr></thead><tbody>
          {#each mounts as row (row.mountpoint)}<tr><td class="mono ink">{row.mountpoint}</td><td><Chip>{row.fstype}</Chip></td><td class="r mono">{humanBytes(row.size)}</td><td class="r mono ink">{humanBytes(row.used)}</td><td class="r usage"><span class="bar" class:alert={row.usePct >= 90}><i style:width={`${Math.min(100, row.usePct)}%`}></i></span><span class="mono">{row.usePct.toFixed(0)}%</span></td></tr>{/each}
        </tbody></table></div>
      {:else}<Empty title={query ? "Nothing matches" : "No filesystems"} body={query ? "Clear the filter to see every filesystem." : "No block-backed mounts were reported."} icon="folder" />{/if}
    {:else if tab === "doctor"}
      <DoctorPanel scan={doctor} loading={doctorLoading} {query} {states} {copied} onrefresh={ondoctorRefresh} {oncopy} {onfix} />
    {:else if tab === "tips"}
      <TipsPanel {tips} {states} {copied} {oncopy} {onfix} />
    {/if}
  {/snippet}
</Tabs>

<style>
  .subnav { margin-bottom: var(--s3); }
  .section-note { margin-bottom: var(--s3); color: var(--ink-mute); font-size: var(--f-small); }
  .section-note.alert { color: var(--alert); }
  .table-wrap { overflow-x: auto; border: 1px solid var(--line-soft); border-radius: var(--radius); background: var(--paper-lift); }
  .table-wrap table { min-width: 680px; }
  .table-wrap th, .table-wrap td { padding-left: var(--s4); }
  .table-wrap th:last-child, .table-wrap td:last-child { padding-right: var(--s4); }
  .dim { color: var(--ink-faint); font-size: var(--f-small); }
  .command-cell { max-width: 420px; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  td.usage { display: flex; align-items: center; justify-content: flex-end; gap: var(--s2); }
  td.usage .bar { width: 90px; }
</style>
