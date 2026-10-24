export interface RawGraphNode {
  id?: unknown;
  label?: unknown;
  group?: unknown;
  size?: unknown;
}

export interface RawGraphLink {
  source?: unknown;
  target?: unknown;
}

export interface GraphNode {
  id: string;
  label: string;
  group: string;
  size: number;
  x: number;
  y: number;
  vx: number;
  vy: number;
  fixed: boolean;
  _fx?: number;
  _fy?: number;
}

export interface GraphLink {
  source: string | GraphNode;
  target: string | GraphNode;
}

export interface GraphModel {
  nodes: GraphNode[];
  links: GraphLink[];
}

export interface LayoutOptions {
  width?: number;
  height?: number;
  repulsion?: number;
  spring?: number;
  springLength?: number;
  gravity?: number;
  damping?: number;
  maxVelocity?: number;
  center?: { x: number; y: number };
}

export interface HeatmapEntry {
  date?: string;
  count?: number;
}

export interface HeatmapDay {
  date: string;
  count: number;
  dow: number;
  week: number;
  future: boolean;
}


export function buildGraphModel(apiJson: unknown): GraphModel {
  const input = apiJson && typeof apiJson === "object" ? apiJson as Record<string, unknown> : {};
  const graph = input.graph && typeof input.graph === "object" ? input.graph as Record<string, unknown> : input;
  const rawNodes = Array.isArray(graph.nodes) ? graph.nodes as RawGraphNode[] : [];
  const rawLinks = Array.isArray(graph.links) ? graph.links as RawGraphLink[] : [];
  const radius = 140;
  const nodes = rawNodes.map((node, index): GraphNode => {
    const angle = (index / Math.max(1, rawNodes.length)) * Math.PI * 2;
    const id = String(node.id ?? index);
    return {
      id,
      label: String(node.label ?? id),
      group: typeof node.group === "string" ? node.group : "",
      size: typeof node.size === "number" && Number.isFinite(node.size) ? node.size : 1,
      x: Math.cos(angle) * radius,
      y: Math.sin(angle) * radius,
      vx: 0,
      vy: 0,
      fixed: false,
    };
  });
  const ids = new Set(nodes.map((node) => node.id));
  const links = rawLinks
    .map((link): GraphLink => ({ source: String(link.source), target: String(link.target) }))
    .filter((link) => link.source !== link.target && ids.has(String(link.source)) && ids.has(String(link.target)));
  return { nodes, links };
}

export function layoutStep(nodes: GraphNode[], links: GraphLink[], opts: LayoutOptions = {}): number {
  const width = opts.width || 600;
  const height = opts.height || 420;
  const repulsion = opts.repulsion ?? 1600;
  const spring = opts.spring ?? 0.02;
  const springLength = opts.springLength ?? 70;
  const gravity = opts.gravity ?? 0.012;
  const damping = opts.damping ?? 0.85;
  const maxVelocity = opts.maxVelocity ?? 40;
  const cx = opts.center ? opts.center.x : width / 2;
  const cy = opts.center ? opts.center.y : height / 2;
  if (!nodes.length) return 0;

  const byId: Record<string, GraphNode> = {};
  for (const node of nodes) {
    byId[node.id] = node;
    node._fx = 0;
    node._fy = 0;
  }

  for (let index = 0; index < nodes.length; index += 1) {
    const a = nodes[index]!;
    for (let other = index + 1; other < nodes.length; other += 1) {
      const b = nodes[other]!;
      let dx = a.x - b.x;
      let dy = a.y - b.y;
      let distanceSquared = dx * dx + dy * dy;
      if (distanceSquared < 0.01) {
        dx = Math.random() - 0.5;
        dy = Math.random() - 0.5;
        distanceSquared = dx * dx + dy * dy + 0.01;
      }
      const distance = Math.sqrt(distanceSquared);
      const force = repulsion / distanceSquared;
      const ux = dx / distance;
      const uy = dy / distance;
      a._fx! += ux * force;
      a._fy! += uy * force;
      b._fx! -= ux * force;
      b._fy! -= uy * force;
    }
  }

  for (const link of links) {
    const source = typeof link.source === "object" ? link.source : byId[link.source];
    const target = typeof link.target === "object" ? link.target : byId[link.target];
    if (!source || !target) continue;
    const dx = target.x - source.x;
    const dy = target.y - source.y;
    const distance = Math.sqrt(dx * dx + dy * dy) || 0.01;
    const force = spring * (distance - springLength);
    const ux = dx / distance;
    const uy = dy / distance;
    source._fx! += ux * force;
    source._fy! += uy * force;
    target._fx! -= ux * force;
    target._fy! -= uy * force;
  }

  let energy = 0;
  for (const node of nodes) {
    node._fx! += (cx - node.x) * gravity;
    node._fy! += (cy - node.y) * gravity;
    if (node.fixed) {
      node.vx = 0;
      node.vy = 0;
      continue;
    }
    node.vx = (node.vx + node._fx!) * damping;
    node.vy = (node.vy + node._fy!) * damping;
    node.vx = Math.max(-maxVelocity, Math.min(maxVelocity, node.vx));
    node.vy = Math.max(-maxVelocity, Math.min(maxVelocity, node.vy));
    node.x += node.vx;
    node.y += node.vy;
    energy += node.vx * node.vx + node.vy * node.vy;
  }
  return energy;
}

function parseDay(value: unknown): Date | null {
  if (!value) return null;
  const match = /^(\d{4})-(\d{2})-(\d{2})/.exec(String(value));
  if (!match) return null;
  return new Date(Date.UTC(Number(match[1]), Number(match[2]) - 1, Number(match[3])));
}

function todayUTC(): Date {
  const now = new Date();
  return new Date(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()));
}

function addDays(date: Date, count: number): Date {
  return new Date(date.getTime() + count * 86_400_000);
}

export function bucketHeatmap(entries: HeatmapEntry[] | null | undefined, weeks = 26, endDate?: string): { weeks: number; days: HeatmapDay[] } {
  const counts: Record<string, number> = {};
  if (Array.isArray(entries)) {
    for (const entry of entries) {
      if (entry?.date) counts[entry.date] = (counts[entry.date] || 0) + (Number(entry.count) || 0);
    }
  }
  const end = parseDay(endDate) || todayUTC();
  const gridEnd = addDays(end, 6 - end.getUTCDay());
  const total = weeks * 7;
  const gridStart = addDays(gridEnd, -(total - 1));
  const days: HeatmapDay[] = [];
  for (let index = 0; index < total; index += 1) {
    const date = addDays(gridStart, index);
    const day = date.toISOString().slice(0, 10);
    const future = date.getTime() > end.getTime();
    days.push({
      date: day,
      count: future ? 0 : counts[day] || 0,
      dow: index % 7,
      week: Math.floor(index / 7),
      future,
    });
  }
  return { weeks, days };
}
