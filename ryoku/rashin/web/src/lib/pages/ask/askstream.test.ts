import { describe, expect, it } from "vitest";
import { readAskStream, type AskMarker } from "./askstream";

function chunked(...chunks: string[]): ReadableStream<Uint8Array> {
  const encoder = new TextEncoder();
  return new ReadableStream({
    start(controller) {
      for (const chunk of chunks) controller.enqueue(encoder.encode(chunk));
      controller.close();
    },
  });
}

describe("readAskStream", () => {
  it("parses markers when chunks split a line", async () => {
    const seen: AskMarker[] = [];
    await readAskStream(
      chunked("@work", "ing looking up the ", "machine\n@ans", 'wer {"id":"a1","text":"RTX 4060","via":"Agent · Luna","needsAgent":false}\n'),
      (marker) => seen.push(marker),
    );

    expect(seen).toEqual([
      { kind: "working", detail: "looking up the machine" },
      { kind: "answer", answer: { id: "a1", text: "RTX 4060", via: "Agent · Luna", needsAgent: false } },
    ]);
  });

  it("keeps embedded JSON escapes and flushes the final unterminated line", async () => {
    const seen: AskMarker[] = [];
    await readAskStream(chunked('@answer {"id":"a2","text":"first\\nsecond"}\n@error cancelled'), (marker) => seen.push(marker));

    expect(seen).toEqual([
      { kind: "answer", answer: { id: "a2", text: "first\nsecond" } },
      { kind: "error", detail: "cancelled" },
    ]);
  });

  it("ignores non-marker output without disturbing later markers", async () => {
    const seen: AskMarker[] = [];
    await readAskStream(chunked("noise\n@working writing\n\n@error cancelled\n"), (marker) => seen.push(marker));

    expect(seen).toEqual([
      { kind: "working", detail: "writing" },
      { kind: "error", detail: "cancelled" },
    ]);
  });
});
