export interface AskAction {
  kind: "file" | "dir" | "url" | "cmd" | "color" | string;
  value: string;
  label: string;
}

export interface AskAnswer {
  id: string;
  text: string;
  images?: string[];
  actions?: AskAction[];
  via?: string;
  needsAgent?: boolean;
  needsAgentReason?: string;
}

export type AskMarker =
  | { kind: "working"; detail: string }
  | { kind: "answer"; answer: AskAnswer }
  | { kind: "error"; detail: string };

const MARKER = /^@(working|answer|error)(?:\s(.*))?$/;

function parseLine(line: string): AskMarker | null {
  const match = MARKER.exec(line.replace(/\r$/, ""));
  if (!match) return null;
  const kind = match[1] as "working" | "answer" | "error";
  const detail = match[2] ?? "";
  if (kind !== "answer") return { kind, detail };
  try {
    return { kind: "answer", answer: JSON.parse(detail) as AskAnswer };
  } catch {
    return { kind: "error", detail: "The daemon returned an unreadable answer." };
  }
}

export async function readAskStream(
  stream: ReadableStream<Uint8Array>,
  onMarker: (marker: AskMarker) => void,
): Promise<void> {
  const reader = stream.getReader();
  const decoder = new TextDecoder();
  let pending = "";

  try {
    while (true) {
      const { done, value } = await reader.read();
      pending += decoder.decode(value, { stream: !done });
      const lines = pending.split("\n");
      pending = lines.pop() ?? "";
      for (const line of lines) {
        const marker = parseLine(line);
        if (marker) onMarker(marker);
      }
      if (done) break;
    }
    if (pending) {
      const marker = parseLine(pending);
      if (marker) onMarker(marker);
    }
  } finally {
    reader.releaseLock();
  }
}
