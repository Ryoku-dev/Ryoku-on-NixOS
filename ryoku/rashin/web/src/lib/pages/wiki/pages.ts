import type { VaultFile } from "$lib/pages/vault/tree";

export function wikiPageName(path: string): string {
  return path.replace(/^wiki\//, "").replace(/\.md$/, "");
}

export function wikiFallbackTitle(path: string): string {
  return wikiPageName(path)
    .split("-")
    .map((word) => word ? word[0]!.toUpperCase() + word.slice(1) : word)
    .join(" ");
}

export function wikiTitle(source: string, path: string): string {
  return /^#\s+(.+)$/m.exec(source)?.[1]?.trim() || wikiFallbackTitle(path);
}

export function wikiFiles(files: VaultFile[]): VaultFile[] {
  return files
    .filter((file) => file.path.startsWith("wiki/") && file.path.endsWith(".md"))
    .sort((left, right) => {
      if (left.path === "wiki/README.md") return -1;
      if (right.path === "wiki/README.md") return 1;
      return left.path.localeCompare(right.path);
    });
}
