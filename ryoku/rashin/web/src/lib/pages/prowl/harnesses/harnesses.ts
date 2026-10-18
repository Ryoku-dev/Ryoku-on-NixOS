import type { Harness } from "$lib/pages/skills/harnesses";
import type { HarnessRow } from "../types";

export interface ChatAgentInfo {
  id: string;
  name: string;
  available: boolean;
  recommended: boolean;
  active: boolean;
}

export type HarnessConnectionState = "unsupported" | "not-connected" | "pending" | "active";

export interface MergedHarness {
  id: string;
  name: string;
  installed: boolean;
  rashinWired: boolean;
  routingSupported: boolean;
  injected: boolean;
  connected: boolean;
  active: boolean;
  pending: boolean;
  credentialStale: boolean;
  state: HarnessConnectionState;
  reason: string;
  files: string[];
  skills: HarnessRow["skills"];
  skillCount: number;
  version?: string;
  model?: string;
  provider?: string;
}

export function connectionState(input: {
  supported: boolean;
  connected: boolean;
  pending: boolean;
}): HarnessConnectionState {
  if (!input.supported) return "unsupported";
  if (!input.connected) return "not-connected";
  if (input.pending) return "pending";
  return "active";
}

export function mergeHarnesses(ledger: Harness[], setup: HarnessRow[]): MergedHarness[] {
  const ledgerById = new Map(ledger.map((row) => [row.id, row]));
  const setupById = new Map(setup.map((row) => [row.id, row]));
  const ids = new Set([...setupById.keys(), ...ledgerById.keys()]);

  return [...ids].map((id) => {
    const local = ledgerById.get(id);
    const remote = setupById.get(id);
    const routingSupported = local?.routing.supported ?? (id !== "gemini" && Boolean(remote));
    const injected = Boolean(remote?.injected || local?.routing.injected);
    const connected = Boolean(local?.routing.connected);
    const active = Boolean(remote?.active || local?.routing.active);
    const pending = Boolean(local?.routing.pending);
    const credentialStale = Boolean(remote?.credentialStale || local?.routing.credentialStale);
    const state = connectionState({ supported: routingSupported, connected: connected || injected, pending });
    return {
      id,
      name: local?.name || remote?.name || id,
      installed: Boolean(local?.present || remote?.detected),
      rashinWired: Boolean(local?.wired),
      routingSupported,
      injected,
      connected,
      active,
      pending,
      credentialStale,
      state,
      reason: local?.routing.note || remote?.note || "",
      files: remote?.files ?? [],
      skills: remote?.skills ?? "unsupported",
      skillCount: local?.skillCount ?? 0,
      version: local?.version,
      model: local?.model,
      provider: local?.provider,
    } satisfies MergedHarness;
  }).sort((a, b) => {
    if (a.installed !== b.installed) return a.installed ? -1 : 1;
    return a.name.localeCompare(b.name);
  });
}

export function stateLabel(state: HarnessConnectionState): string {
  switch (state) {
    case "unsupported": return "Prowl plug-in unavailable";
    case "not-connected": return "Not connected";
    case "pending": return "Prowl default waiting";
    case "active": return "Connected";
  }
}

export function skillsActionable(status: HarnessRow["skills"]): boolean {
  return status === "install" || status === "update" || status === "conflict" || status === "error";
}
