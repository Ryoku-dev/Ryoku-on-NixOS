import type { IconName } from "$lib/ui/icons";

const ICON_BY_TOOL: Record<string, IconName> = {
  read: "file",
  edit: "edit",
  execute: "terminal",
  search: "search",
  fetch: "external",
  think: "thought",
};

export function toolIcon(kind: string): IconName {
  return ICON_BY_TOOL[kind.toLowerCase()] ?? "tool";
}

export function relativeTime(value?: string, now = Date.now()): string {
  if (!value) return "";
  const stamp = Date.parse(value);
  if (!Number.isFinite(stamp)) return "";
  const elapsed = Math.max(0, now - stamp);
  const minute = 60_000;
  const hour = 60 * minute;
  const day = 24 * hour;
  if (elapsed < minute) return "now";
  if (elapsed < hour) return `${Math.floor(elapsed / minute)}m`;
  if (elapsed < day) return `${Math.floor(elapsed / hour)}h`;
  if (elapsed < 7 * day) return `${Math.floor(elapsed / day)}d`;
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric" }).format(stamp);
}

export function tokenLabel(value: number): string {
  return new Intl.NumberFormat(undefined, { notation: value >= 10_000 ? "compact" : "standard" }).format(value);
}
