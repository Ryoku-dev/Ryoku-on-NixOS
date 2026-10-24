import { describe, expect, it } from "vitest";
import { bucketHeatmap, buildGraphModel, layoutStep, type GraphNode } from "./graph";

describe("buildGraphModel", () => {
  it("tolerates an empty graph", () => {
    for (const input of [undefined, null, {}, { graph: {} }, { graph: { nodes: [], links: [] } }]) {
      const model = buildGraphModel(input);
      expect(model.nodes).toEqual([]);
      expect(model.links).toEqual([]);
    }
  });

  it("normalizes nodes and drops dangling links", () => {
    const model = buildGraphModel({
      graph: {
        nodes: [{ id: "AGENTS.md", label: "AGENTS", group: "hub", size: 1197 }, { id: "a.md" }],
        links: [
          { source: "AGENTS.md", target: "a.md" },
          { source: "AGENTS.md", target: "ghost.md" },
          { source: "a.md", target: "a.md" },
        ],
      },
    });
    expect(model.nodes).toHaveLength(2);
    expect(model.nodes[1]!.label).toBe("a.md");
    expect(model.links).toHaveLength(1);
    expect(model.links[0]!.target).toBe("a.md");
  });
});

describe("layoutStep", () => {
  it("moves connected nodes closer over 50 ticks", () => {
    const nodes = [
      { id: "a", x: -250, y: 0, vx: 0, vy: 0, size: 1, label: "a", group: "", fixed: false },
      { id: "b", x: 250, y: 0, vx: 0, vy: 0, size: 1, label: "b", group: "", fixed: false },
    ] satisfies GraphNode[];
    const links = [{ source: "a", target: "b" }];
    const options = { width: 600, height: 420, center: { x: 0, y: 0 } };
    const before = Math.hypot(nodes[0]!.x - nodes[1]!.x, nodes[0]!.y - nodes[1]!.y);
    for (let index = 0; index < 50; index += 1) layoutStep(nodes, links, options);
    const after = Math.hypot(nodes[0]!.x - nodes[1]!.x, nodes[0]!.y - nodes[1]!.y);
    expect(after).toBeLessThan(before);
    expect(after).toBeLessThan(200);
  });

  it("respects fixed nodes", () => {
    const nodes = [
      { id: "a", x: 0, y: 0, vx: 0, vy: 0, size: 1, label: "a", group: "", fixed: true },
      { id: "b", x: 100, y: 0, vx: 0, vy: 0, size: 1, label: "b", group: "", fixed: false },
    ] satisfies GraphNode[];
    layoutStep(nodes, [{ source: "a", target: "b" }], { center: { x: 300, y: 210 } });
    expect(nodes[0]!.x).toBe(0);
    expect(nodes[0]!.y).toBe(0);
  });

  it("returns zero for no nodes", () => {
    expect(layoutStep([], [], {})).toBe(0);
  });
});

describe("bucketHeatmap", () => {
  it("builds a complete Sunday-first grid ending on the supplied day", () => {
    const model = bucketHeatmap([], 26, "2026-07-02");
    expect(model.weeks).toBe(26);
    expect(model.days).toHaveLength(26 * 7);
    expect(model.days[0]!.dow).toBe(0);
    const past = model.days.filter((day) => !day.future);
    expect(past.at(-1)?.date).toBe("2026-07-02");
  });

  it("fills gaps and applies provided counts", () => {
    const model = bucketHeatmap([
      { date: "2026-07-02", count: 3 },
      { date: "2026-06-30", count: 1 },
    ], 26, "2026-07-02");
    const byDate = Object.fromEntries(model.days.map((day) => [day.date, day]));
    expect(byDate["2026-07-02"]!.count).toBe(3);
    expect(byDate["2026-06-30"]!.count).toBe(1);
    expect(byDate["2026-07-01"]!.count).toBe(0);
  });

  it("clears cells after the end date", () => {
    const model = bucketHeatmap([{ date: "2026-07-05", count: 9 }], 26, "2026-07-02");
    const future = model.days.filter((day) => day.future);
    expect(future.length).toBeGreaterThan(0);
    for (const day of future) expect(day.count).toBe(0);
  });
});
