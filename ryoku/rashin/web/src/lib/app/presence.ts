import type { NeedleMood } from "$lib/fx/NeedleFace.svelte";

interface LanePresence {
  busy: boolean;
  activity: string;
  permissions: unknown[];
  banner: { state: string };
}

export interface CombinedPresence {
  mood: NeedleMood;
  label: string;
}

export function combinedPresence(
  online: boolean,
  ryoku: LanePresence,
  chat: LanePresence,
  ryokuConnected: boolean,
  chatConnected: boolean,
): CombinedPresence {
  if (!online) return { mood: "sleeping", label: "daemon offline" };

  if (ryoku.permissions.length > 0 || chat.permissions.length > 0) {
    return { mood: "waiting", label: "waiting for approval" };
  }

  const active = ryoku.busy ? ryoku : chat.busy ? chat : null;
  if (active) {
    const activity = active.activity || "working";
    return { mood: activity === "thinking" ? "thinking" : "working", label: activity };
  }

  if (ryoku.banner.state === "dead" && chat.banner.state === "dead") {
    return { mood: "sleeping", label: "agent down" };
  }
  if (ryoku.banner.state === "starting" || chat.banner.state === "starting") {
    return { mood: "thinking", label: "waking" };
  }
  return { mood: "idle", label: ryokuConnected && chatConnected ? "listening" : "connecting" };
}
