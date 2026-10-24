import { describe, expect, it } from "vitest";
import { filterCategories } from "./filter";

const categories = [
  {
    name: "software-development",
    skills: [
      { name: "test-driven-development", description: "write tests first" },
      { name: "systematic-debugging", description: "root-cause failures" },
    ],
  },
  {
    name: "writing",
    skills: [{ name: "writing-plans", description: "plan before code" }],
  },
];

describe("filterCategories", () => {
  it("returns every category unchanged for a blank query", () => {
    for (const query of ["", "   ", null, undefined]) {
      const result = filterCategories(categories, query);
      expect(result).toHaveLength(2);
      expect(result[0]!.skills).toHaveLength(2);
    }
  });

  it("filters names case-insensitively", () => {
    const result = filterCategories(categories, "DEBUG");
    expect(result).toHaveLength(1);
    expect(result[0]!.name).toBe("software-development");
    expect(result[0]!.skills).toHaveLength(1);
    expect(result[0]!.skills[0]!.name).toBe("systematic-debugging");
  });

  it("filters descriptions", () => {
    const result = filterCategories(categories, "plan before");
    expect(result).toHaveLength(1);
    expect(result[0]!.name).toBe("writing");
  });

  it("drops empty categories", () => {
    expect(filterCategories(categories, "zzz-nothing")).toEqual([]);
  });

  it("tolerates missing skills and non-array input", () => {
    expect(filterCategories(null, "x")).toEqual([]);
    expect(filterCategories([{ name: "empty" }], "x")).toEqual([]);
  });
});
