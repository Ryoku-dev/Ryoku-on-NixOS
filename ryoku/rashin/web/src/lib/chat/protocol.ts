// The /ws/chat wire contract (ryoku/rashin/backend/ws.go): wsOut frames from
// the daemon, wsIn commands from a surface. The reducer in chatstate.js folds
// frames into the transcript; this file only names the shapes.

export interface ModelInfo {
  id: string;
  name: string;
  description?: string;
}

export interface CommandInfo {
  name: string;
  description: string;
  hint?: string;
}

export interface SessionMeta {
  id: string;
  title: string;
  cwd?: string;
  updatedAt?: string;
}

export interface PermOption {
  id: string;
  name: string;
  kind: string;
}

export interface ToolDiff {
  path: string;
  old?: string;
  new: string;
}

export interface PromptImage {
  data: string;
  mimeType: string;
}
export interface HandoffInput {
  askId: string;
  question: string;
  answer: string;
  run: boolean;
}


export type BannerState = "starting" | "ready" | "busy" | "dead" | "";

/** what runs without asking: nothing, reads, or everything */
export type ApprovalsMode = "ask" | "read-only" | "auto";

export interface WsOut {
  type: string;
  state?: BannerState;
  error?: string;
  text?: string;
  id?: string;
  title?: string;
  kind?: string;
  status?: string;
  input?: string;
  output?: string;
  diffs?: ToolDiff[];
  auto?: boolean;
  toolId?: string;
  requestId?: string;
  options?: PermOption[];
  outcome?: string;
  mode?: string;
  stopReason?: string;
  models?: ModelInfo[];
  current?: string;
  pick?: string;
  pickUnavailable?: boolean;
  agent?: string;
  prowl?: "active" | "pending";
  reason?: string;
  commands?: CommandInfo[];
  sessionId?: string;
  askId?: string;
  answer?: string;
  size?: number;
  used?: number;
  sessions?: SessionMeta[];
  // The author's own turn, folded locally before the daemon echoes it.
  images?: PromptImage[];
}

export type WsIn =
  | { type: "user"; text: string; images?: PromptImage[] }
  | ({ type: "handoff" } & HandoffInput)
  | { type: "cancel" }
  | { type: "new" }
  | { type: "history" }
  | { type: "load"; sessionId: string }
  | { type: "set_model"; modelId: string }
  | { type: "permission"; requestId: string; optionId: string }
  | { type: "approvals"; mode: ApprovalsMode };

export type ToolStatus = "pending" | "in_progress" | "completed" | "failed" | "cancelled" | string;
