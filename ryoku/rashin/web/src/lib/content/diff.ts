export type DiffLineKind = "context" | "add" | "remove";

export interface DiffLine {
  kind: DiffLineKind;
  text: string;
  oldNumber?: number;
  newNumber?: number;
}

export interface DiffHunk {
  oldStart: number;
  oldCount: number;
  newStart: number;
  newCount: number;
  lines: DiffLine[];
}

export interface UnifiedDiff {
  hunks: DiffHunk[];
  added: number;
  removed: number;
}

type Edit = { kind: DiffLineKind; text: string };

function linesOf(source: string): string[] {
  if (!source) return [];
  const lines = source.replace(/\r\n?/g, "\n").split("\n");
  if (lines.at(-1) === "") lines.pop();
  return lines;
}


/** Myers' line diff. It keeps memory proportional to edit distance, not file area. */
function editScript(before: string[], after: string[]): Edit[] {
  const endX = before.length;
  const endY = after.length;
  if (endX === 0) return after.map((text) => ({ kind: "add", text }));
  if (endY === 0) return before.map((text) => ({ kind: "remove", text }));

  let frontier = new Map<number, number>([[0, 0]]);
  const trace: Map<number, number>[] = [];
  const limit = endX + endY;

  for (let distance = 0; distance <= limit; distance += 1) {
    trace.push(frontier);
    const next = new Map<number, number>();
    for (let diagonal = -distance; diagonal <= distance; diagonal += 2) {
      let x: number;
      if (
        diagonal === -distance ||
        (diagonal !== distance &&
          (frontier.get(diagonal - 1) ?? Number.NEGATIVE_INFINITY) <
            (frontier.get(diagonal + 1) ?? Number.NEGATIVE_INFINITY))
      ) {
        x = frontier.get(diagonal + 1) ?? 0;
      } else {
        x = (frontier.get(diagonal - 1) ?? -1) + 1;
      }
      let y = x - diagonal;
      while (x < endX && y < endY && before[x] === after[y]) {
        x += 1;
        y += 1;
      }
      next.set(diagonal, x);
      if (x >= endX && y >= endY) return backtrack(trace, before, after, distance);
    }
    frontier = next;
  }
  return [];
}

function backtrack(
  trace: Map<number, number>[],
  before: string[],
  after: string[],
  distance: number,
): Edit[] {
  const edits: Edit[] = [];
  let x = before.length;
  let y = after.length;

  for (let d = distance; d >= 0; d -= 1) {
    const frontier = trace[d]!;
    const diagonal = x - y;
    const previousDiagonal =
      diagonal === -d ||
      (diagonal !== d &&
        (frontier.get(diagonal - 1) ?? Number.NEGATIVE_INFINITY) <
          (frontier.get(diagonal + 1) ?? Number.NEGATIVE_INFINITY))
        ? diagonal + 1
        : diagonal - 1;
    const previousX = frontier.get(previousDiagonal) ?? 0;
    const previousY = previousX - previousDiagonal;

    while (x > previousX && y > previousY) {
      edits.push({ kind: "context", text: before[x - 1]! });
      x -= 1;
      y -= 1;
    }
    if (d === 0) break;
    if (x === previousX) {
      edits.push({ kind: "add", text: after[y - 1]! });
      y -= 1;
    } else {
      edits.push({ kind: "remove", text: before[x - 1]! });
      x -= 1;
    }
  }
  return edits.reverse();
}

function numberLines(edits: Edit[]): DiffLine[] {
  let oldNumber = 1;
  let newNumber = 1;
  return edits.map((edit) => {
    if (edit.kind === "add") return { ...edit, newNumber: newNumber++ };
    if (edit.kind === "remove") return { ...edit, oldNumber: oldNumber++ };
    return { ...edit, oldNumber: oldNumber++, newNumber: newNumber++ };
  });
}

export function splitHunks(lines: DiffLine[], context = 3): DiffHunk[] {
  const changes: number[] = [];
  for (let index = 0; index < lines.length; index += 1) {
    if (lines[index]!.kind !== "context") changes.push(index);
  }
  if (changes.length === 0) return [];

  const ranges: Array<[number, number]> = [];
  let start = Math.max(0, changes[0]! - context);
  let end = Math.min(lines.length, changes[0]! + context + 1);
  for (const changedAt of changes.slice(1)) {
    const nextStart = Math.max(0, changedAt - context);
    const nextEnd = Math.min(lines.length, changedAt + context + 1);
    if (nextStart <= end) end = Math.max(end, nextEnd);
    else {
      ranges.push([start, end]);
      start = nextStart;
      end = nextEnd;
    }
  }
  ranges.push([start, end]);

  return ranges.map(([from, to]) => {
    const hunkLines = lines.slice(from, to);
    const first = hunkLines[0]!;
    return {
      oldStart: first.oldNumber ?? Math.max(0, (first.newNumber ?? 1) - 1),
      oldCount: hunkLines.reduce((count, line) => count + (line.kind === "add" ? 0 : 1), 0),
      newStart: first.newNumber ?? Math.max(0, (first.oldNumber ?? 1) - 1),
      newCount: hunkLines.reduce((count, line) => count + (line.kind === "remove" ? 0 : 1), 0),
      lines: hunkLines,
    };
  });
}

export function createUnifiedDiff(before: string, after: string, context = 3): UnifiedDiff {
  const edits = editScript(linesOf(before), linesOf(after));
  return {
    hunks: splitHunks(numberLines(edits), context),
    added: edits.reduce((count, edit) => count + (edit.kind === "add" ? 1 : 0), 0),
    removed: edits.reduce((count, edit) => count + (edit.kind === "remove" ? 1 : 0), 0),
  };
}
