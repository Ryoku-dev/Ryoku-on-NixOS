// The console wears the desktop's palette. /api/theme resolves the Material
// roles through the same chain Tokens.qml uses (named scheme, then the
// wallpaper, then the signature default); this maps them onto app.css's
// tokens and repaints when the wallpaper or scheme changes.

import { api } from "$lib/api/client";

const ROLE_VARS: Record<string, string> = {
  surface: "--paper",
  surfaceContainerLow: "--paper-lift",
  onSurface: "--ink",
  onSurfaceVariant: "--ink-dim",
  inverseSurface: "--bone",
  inverseOnSurface: "--ink-on-bone",
  primary: "--sun",
};

export interface Wallpaper {
  available: boolean;
  kind: "image" | "video" | string;
  rev: string;
}

interface ThemeAnswer {
  roles?: Record<string, string>;
  reduceMotion?: boolean;
  wallpaper?: Partial<Wallpaper>;
}

const HEX = /^#[0-9a-f]{6}([0-9a-f]{2})?$/i;

/** A surface brighter than mid-grey is a light scheme, and native controls follow it. */
export function isLight(hex: string | undefined): boolean {
  const m = /^#([0-9a-f]{2})([0-9a-f]{2})([0-9a-f]{2})/i.exec(hex || "");
  if (!m) return false;
  const [r, g, b] = m.slice(1).map((h) => parseInt(h, 16) / 255) as [number, number, number];
  return 0.299 * r + 0.587 * g + 0.114 * b > 0.5;
}

export function applyRoles(roles: Record<string, string> | undefined, style: CSSStyleDeclaration): void {
  for (const [role, cssVar] of Object.entries(ROLE_VARS)) {
    const v = roles?.[role];
    if (typeof v === "string" && HEX.test(v)) style.setProperty(cssVar, v);
  }
  style.setProperty("color-scheme", isLight(roles?.surface) ? "light" : "dark");
}

export class ThemeStore {
  light = $state(false);
  reduceMotion = $state(false);
  wallpaper = $state<Wallpaper | null>(null);
  /** bumps when the roles change, so canvases repaint their ink */
  rev = $state(0);
  private lastRoles = "";
  private timer: number | null = null;

  async refresh(): Promise<void> {
    let t: ThemeAnswer;
    try {
      t = (await api.theme()) as ThemeAnswer;
    } catch {
      return;
    }
    const roles = JSON.stringify(t.roles ?? {});
    if (roles !== this.lastRoles) {
      this.lastRoles = roles;
      applyRoles(t.roles, document.documentElement.style);
      this.light = isLight(t.roles?.surface);
      this.rev++;
    }
    this.reduceMotion = !!t.reduceMotion;
    document.documentElement.classList.toggle("reduce-motion", this.reduceMotion);
    const w = t.wallpaper;
    const next: Wallpaper | null = w?.available ? { available: true, kind: w.kind ?? "image", rev: w.rev ?? "" } : null;
    if (JSON.stringify(next) !== JSON.stringify(this.wallpaper)) this.wallpaper = next;
  }

  start(): void {
    void this.refresh();
    this.timer = window.setInterval(() => {
      if (!document.hidden) void this.refresh();
    }, 15000);
    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) void this.refresh();
    });
  }

  stop(): void {
    clearInterval(this.timer ?? undefined);
    this.timer = null;
  }
}

export const theme = new ThemeStore();
