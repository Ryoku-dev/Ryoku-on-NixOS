import { describe, expect, it } from "vitest";
import { createUnifiedDiff } from "./diff";

describe("createUnifiedDiff", () => {
  it("counts added and removed lines", () => {
    const result = createUnifiedDiff("alpha\nbeta\ngamma\n", "alpha\nBETA\ngamma\ndelta\n");

    expect(result.added).toBe(2);
    expect(result.removed).toBe(1);
    expect(result.hunks).toHaveLength(1);
    expect(result.hunks[0]!.lines.map((line) => line.kind)).toEqual([
      "context",
      "remove",
      "add",
      "context",
      "add",
    ]);
  });

  it("splits distant changes into separate hunks", () => {
    const before = Array.from({ length: 16 }, (_, index) => `line ${index + 1}`).join("\n");
    const after = before.replace("line 2", "line two").replace("line 15", "line fifteen");
    const result = createUnifiedDiff(before, after, 2);

    expect(result.hunks).toHaveLength(2);
    expect(result.hunks[0]).toMatchObject({ oldStart: 1, oldCount: 4, newStart: 1, newCount: 4 });
    expect(result.hunks[1]).toMatchObject({ oldStart: 13, oldCount: 4, newStart: 13, newCount: 4 });
  });

  it("merges nearby changes when their context overlaps", () => {
    const before = "a\nb\nc\nd\ne\nf\ng\n";
    const after = "a\nB\nc\nd\nE\nf\ng\n";
    const result = createUnifiedDiff(before, after, 2);

    expect(result.hunks).toHaveLength(1);
    expect(result.hunks[0]).toMatchObject({ oldStart: 1, oldCount: 7, newStart: 1, newCount: 7 });
  });

  it("uses zero as the empty side start for a whole-file addition", () => {
    const result = createUnifiedDiff("", "first\nsecond\n");

    expect(result).toMatchObject({ added: 2, removed: 0 });
    expect(result.hunks[0]).toMatchObject({ oldStart: 0, oldCount: 0, newStart: 1, newCount: 2 });
  });
});
