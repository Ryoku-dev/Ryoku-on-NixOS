export interface SectionMeta {
  collectedAt: string;
  note?: string;
}

export interface UnitRow {
  name: string;
  loadState?: string;
  activeState: string;
  subState?: string;
  description?: string;
}

export interface ServiceSection extends SectionMeta {
  running: UnitRow[];
  stopped: UnitRow[];
  userOnly: UnitRow[];
  runningN: number;
  totalN: number;
}

export interface TimerRow {
  unit: string;
  activates?: string;
  nextRun: string;
  left?: string;
  last?: string;
  passive: boolean;
}

export interface TimerSection extends SectionMeta {
  active: TimerRow[];
  passive: TimerRow[];
}

export interface CronEntry {
  schedule: string;
  command: string;
  origin: string;
}

export interface ScheduleSection extends SectionMeta {
  crontabs: CronEntry[];
  anacron: CronEntry[];
  atJobs: CronEntry[];
  cronActive?: boolean;
}

export interface ContainerRow {
  id: string;
  name: string;
  image: string;
  status: string;
  state: string;
  created: string;
}

export interface ContainerSection extends SectionMeta {
  rows: ContainerRow[];
  runningN: number;
  totalN: number;
  installed: boolean;
}

export interface ListenerRow {
  proto: string;
  address: string;
  port: number;
  process?: string;
  loopback: boolean;
}

export interface ListenerSection extends SectionMeta { rows: ListenerRow[]; }

export interface ProcessRow {
  pid: number;
  command: string;
  cpuPct: number;
  memRss: number;
}

export interface ProcessSection extends SectionMeta { rows: ProcessRow[]; }

export interface MountRow {
  device: string;
  mountpoint: string;
  fstype: string;
  size: number;
  used: number;
  usePct: number;
}

export interface MountSection extends SectionMeta { rows: MountRow[]; }

export interface Tip {
  id: string;
  severity: "info" | "watch" | "act" | string;
  title: string;
  detail: string;

  command?: string;
}

export interface SystemInventory {
  collectedAt: string;
  services: ServiceSection;
  timers: TimerSection;
  schedules: ScheduleSection;
  containers: ContainerSection;
  listeners: ListenerSection;
  processes: ProcessSection;
  mounts: MountSection;
  tips: Tip[];
}
export function normalizeInventory(value: SystemInventory): SystemInventory {
  return {
    ...value,
    services: {
      ...value.services,
      running: value.services.running ?? [],
      stopped: value.services.stopped ?? [],
      userOnly: value.services.userOnly ?? [],
    },
    timers: {
      ...value.timers,
      active: value.timers.active ?? [],
      passive: value.timers.passive ?? [],
    },
    schedules: {
      ...value.schedules,
      crontabs: value.schedules.crontabs ?? [],
      anacron: value.schedules.anacron ?? [],
      atJobs: value.schedules.atJobs ?? [],
    },
    containers: { ...value.containers, rows: value.containers.rows ?? [] },
    listeners: { ...value.listeners, rows: value.listeners.rows ?? [] },
    processes: { ...value.processes, rows: value.processes.rows ?? [] },
    mounts: { ...value.mounts, rows: value.mounts.rows ?? [] },
    tips: value.tips ?? [],
  };
}

export function humanBytes(value: number): string {
  const n = Number(value) || 0;
  if (n < 1024) return `${n} B`;
  const units = ["KiB", "MiB", "GiB", "TiB"];
  let amount = n;
  let unit = -1;
  do {
    amount /= 1024;
    unit++;
  } while (amount >= 1024 && unit < units.length - 1);
  return `${amount.toFixed(amount >= 10 ? 0 : 1)} ${units[unit]}`;
}

export function ago(iso: string | undefined): string {
  if (!iso) return "—";
  const seconds = (Date.now() - new Date(iso).getTime()) / 1000;
  if (!Number.isFinite(seconds) || seconds < 0) return "—";
  if (seconds < 45) return "just now";
  if (seconds < 3600) return `${Math.round(seconds / 60)} min ago`;
  if (seconds < 86400) return `${Math.round(seconds / 3600)} h ago`;
  return `${Math.round(seconds / 86400)} d ago`;
}

export function shortDate(value: string): string {
  if (!value || value === "-") return "—";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return date.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
}

export function isWildAddress(address: string): boolean {
  return address === "*" || address === "::" || address === "0.0.0.0";
}
