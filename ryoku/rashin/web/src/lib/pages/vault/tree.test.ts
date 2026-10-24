import { describe, expect, it } from "vitest";
import { groupVaultFiles, type VaultFile } from "./tree";

function file(path: string): VaultFile {
  return { path, size: 1, mtime: "2026-10-05T00:00:00Z", generated: true };
}

describe("groupVaultFiles", () => {
  it("gives generated wiki pages their own group", () => {
    const groups = groupVaultFiles([
      file("wiki/README.md"),
      file("wiki/linux-basics.md"),
      file("desktop.md"),
      file("notes.txt"),
    ]);

    expect(groups.find((group) => group.key === "wiki")).toEqual({
      key: "wiki",
      label: "Wiki",
      prefix: "wiki/",
      files: [file("wiki/README.md"), file("wiki/linux-basics.md")],
    });
    expect(groups.find((group) => group.key === "other")?.files).toEqual([file("notes.txt")]);
  });
});
