export interface VaultFile {
  path: string;
  size: number;
  mtime: string;
  generated: boolean;
}

export interface VaultGroup {
  key: string;
  label: string;
  files: VaultFile[];
  prefix: string;
}

export interface VaultTreeRow {
  kind: "folder" | "file";
  key: string;
  name: string;
  depth: number;
  file?: VaultFile;
  open?: boolean;
}

interface FolderNode {
  folders: Record<string, FolderNode>;
  files: Array<{ file: VaultFile; name: string }>;
}

export function groupVaultFiles(files: VaultFile[]): VaultGroup[] {
  const visible = files.filter((file) => file.path !== "CLAUDE.md");
  const maps = visible.filter((file) => !file.path.includes("/") && file.path.endsWith(".md"));
  const wiki = visible.filter((file) => file.path.startsWith("wiki/"));
  const memory = visible.filter((file) => file.path.startsWith("memory/"));
  const journal = visible
    .filter((file) => file.path.startsWith("journal/"))
    .sort((a, b) => Date.parse(b.mtime) - Date.parse(a.mtime));
  const source = visible.filter((file) => file.path.startsWith("source/"));
  const claimed = new Set([...maps, ...wiki, ...memory, ...journal, ...source]);
  const other = visible.filter((file) => !claimed.has(file));
  const groups: VaultGroup[] = [
    { key: "wiki", label: "Wiki", files: wiki, prefix: "wiki/" },
    { key: "maps", label: "Maps", files: maps, prefix: "" },
    { key: "memory", label: "Memory", files: memory, prefix: "memory/" },
    { key: "journal", label: "Journal", files: journal, prefix: "journal/" },
    { key: "source", label: "Source mirror", files: source, prefix: "source/" },
  ];
  if (other.length) groups.push({ key: "other", label: "Other", files: other, prefix: "" });
  return groups;
}

export function flattenVaultGroup(
  group: VaultGroup,
  openFolders: Set<string>,
  query: string,
  journalExpanded: boolean,
): VaultTreeRow[] {
  const needle = query.trim().toLowerCase();
  let files = needle
    ? group.files.filter((file) => file.path.split("/").at(-1)?.toLowerCase().includes(needle))
    : group.files;
  if (group.key === "journal" && !journalExpanded && !needle) files = files.slice(0, 8);

  const root: FolderNode = { folders: {}, files: [] };
  for (const file of files) {
    const relative = group.prefix && file.path.startsWith(group.prefix) ? file.path.slice(group.prefix.length) : file.path;
    const parts = relative.split("/");
    const name = parts.pop() || relative;
    let node = root;
    for (const folder of parts) node = (node.folders[folder] ||= { folders: {}, files: [] });
    node.files.push({ file, name });
  }

  const rows: VaultTreeRow[] = [];
  const visit = (node: FolderNode, depth: number, parentKey: string) => {
    for (const name of Object.keys(node.folders).sort()) {
      const key = `${group.key}/${parentKey}${name}`;
      const open = Boolean(needle) || openFolders.has(key);
      rows.push({ kind: "folder", key, name, depth, open });
      if (open) visit(node.folders[name]!, depth + 1, `${parentKey}${name}/`);
    }
    for (const entry of node.files) {
      rows.push({ kind: "file", key: entry.file.path, name: entry.name, depth, file: entry.file });
    }
  };
  visit(root, 0, "");
  return rows;
}

export function humanBytes(bytes: number): string {
  if (!Number.isFinite(bytes) || bytes <= 0) return "0 B";
  const units = ["B", "KB", "MB", "GB"];
  const power = Math.min(Math.floor(Math.log(bytes) / Math.log(1024)), units.length - 1);
  const value = bytes / 1024 ** power;
  return `${value >= 10 || power === 0 ? value.toFixed(0) : value.toFixed(1)} ${units[power]}`;
}
