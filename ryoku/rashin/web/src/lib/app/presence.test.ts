import { describe, expect, it } from "vitest";
import { combinedPresence } from "./presence";

function lane(overrides: Partial<Parameters<typeof combinedPresence>[1]> = {}): Parameters<typeof combinedPresence>[1] {
  return {
    busy: false,
    activity: "",
    permissions: [],
    banner: { state: "ready" },
    ...overrides,
  };
}

describe("combinedPresence", () => {
  it("reports work from either lane", () => {
    expect(combinedPresence(true, lane(), lane({ busy: true, activity: "reading" }), true, true)).toEqual({
      mood: "working",
      label: "reading",
    });
  });

  it("gives an open approval priority across both lanes", () => {
    expect(combinedPresence(true, lane({ busy: true }), lane({ permissions: [{}] }), true, true)).toEqual({
      mood: "waiting",
      label: "waiting for approval",
    });
  });

  it("is only listening when both lane sockets are connected", () => {
    expect(combinedPresence(true, lane(), lane(), true, false)).toEqual({
      mood: "idle",
      label: "connecting",
    });
  });
});
