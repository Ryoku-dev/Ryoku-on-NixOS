<script lang="ts">
  import { onDestroy, onMount } from "svelte";
  import Button from "$lib/ui/Button.svelte";
  import { layoutStep, type GraphLink, type GraphModel, type GraphNode } from "./graph";

  interface Props {
    model: GraphModel;
    selected?: string | null;
    onselect?: (node: GraphNode | null) => void;
  }

  let { model, selected = null, onselect }: Props = $props();
  let canvas: HTMLCanvasElement;
  let status = $state<"running" | "paused" | "settled">("settled");
  let hover = $state<string | null>(null);
  let width = 0;
  let height = 0;
  let frame = 0;
  let settledFrames = 0;
  let observer: ResizeObserver | undefined;
  let reduced = false;
  let mounted = false;
  let activeModel: GraphModel | null = null;
  const degree = new Map<string, number>();
  const nodesById = new Map<string, GraphNode>();

  function linkNode(endpoint: string | GraphNode): GraphNode | undefined {
    return typeof endpoint === "object" ? endpoint : nodesById.get(endpoint);
  }

  function rebuildIndex(): void {
    degree.clear();
    nodesById.clear();
    for (const node of model.nodes) {
      nodesById.set(node.id, node);
      degree.set(node.id, 0);
    }
    for (const link of model.links) {
      const source = typeof link.source === "object" ? link.source.id : link.source;
      const target = typeof link.target === "object" ? link.target.id : link.target;
      degree.set(source, (degree.get(source) || 0) + 1);
      degree.set(target, (degree.get(target) || 0) + 1);
    }
  }

  function nodeRadius(node: GraphNode): number {
    return Math.min(10, 3.5 + Math.sqrt(degree.get(node.id) || 0) * 1.45);
  }

  function seed(): void {
    const radius = Math.min(width, height) * 0.32;
    model.nodes.forEach((node, index) => {
      const angle = (index / Math.max(1, model.nodes.length)) * Math.PI * 2;
      const spread = radius * (0.64 + 0.36 * ((index % 5) / 5));
      node.x = width / 2 + Math.cos(angle) * spread;
      node.y = height / 2 + Math.sin(angle) * spread;
      node.vx = 0;
      node.vy = 0;
      node.fixed = false;
    });
  }

  function colors(): { ink: string; dim: string; faint: string; line: string; paper: string } {
    const style = getComputedStyle(document.documentElement);
    return {
      ink: style.getPropertyValue("--ink").trim(),
      dim: style.getPropertyValue("--ink-dim").trim(),
      faint: style.getPropertyValue("--ink-faint").trim(),
      line: style.getPropertyValue("--line").trim(),
      paper: style.getPropertyValue("--paper").trim(),
    };
  }

  function draw(): void {
    const context = canvas?.getContext("2d");
    if (!context || !width || !height) return;
    const palette = colors();
    context.clearRect(0, 0, width, height);
    if (!model.nodes.length) return;

    context.save();
    context.strokeStyle = palette.line;
    context.lineWidth = 1;
    for (const link of model.links) {
      const source = linkNode(link.source);
      const target = linkNode(link.target);
      if (!source || !target) continue;
      context.beginPath();
      context.moveTo(source.x, source.y);
      context.lineTo(target.x, target.y);
      context.stroke();
    }
    context.restore();

    for (const node of model.nodes) {
      const radius = nodeRadius(node);
      context.beginPath();
      context.arc(node.x, node.y, radius, 0, Math.PI * 2);
      context.fillStyle = palette.ink;
      context.globalAlpha = selected && selected !== node.id ? 0.55 : 1;
      context.fill();
      if (selected === node.id) {
        context.strokeStyle = palette.dim;
        context.lineWidth = 1;
        context.stroke();
      }
      if (hover === node.id || selected === node.id) {
        context.globalAlpha = 1;
        context.fillStyle = palette.dim;
        context.font = `11px ${getComputedStyle(document.documentElement).getPropertyValue("--mono")}`;
        context.textAlign = "center";
        context.textBaseline = "top";
        const label = node.label.length > 28 ? `${node.label.slice(0, 27)}…` : node.label;
        context.fillText(label, node.x, node.y + radius + 5);
      }
    }
    context.globalAlpha = 1;
  }

  function tick(): void {
    frame = 0;
    if (status !== "running") return;
    const energy = layoutStep(model.nodes, model.links, {
      width,
      height,
      center: { x: width / 2, y: height / 2 },
    });
    draw();
    settledFrames = energy < 0.6 ? settledFrames + 1 : 0;
    if (settledFrames > 20) {
      status = "settled";
      return;
    }
    frame = requestAnimationFrame(tick);
  }

  function start(): void {
    if (reduced || !model.nodes.length) {
      status = "settled";
      draw();
      return;
    }
    status = "running";
    if (!frame) frame = requestAnimationFrame(tick);
  }

  function settleImmediately(): void {
    for (let index = 0; index < 140; index += 1) {
      layoutStep(model.nodes, model.links, { width, height, center: { x: width / 2, y: height / 2 } });
    }
    status = "settled";
    draw();
  }

  function rerun(): void {
    if (frame) cancelAnimationFrame(frame);
    frame = 0;
    settledFrames = 0;
    rebuildIndex();
    seed();
    if (reduced) settleImmediately();
    else start();
  }

  function togglePause(): void {
    if (status === "running") {
      status = "paused";
      if (frame) cancelAnimationFrame(frame);
      frame = 0;
      draw();
    } else {
      settledFrames = 0;
      start();
    }
  }

  function resize(): void {
    if (!canvas) return;
    const nextWidth = canvas.clientWidth || 600;
    const nextHeight = canvas.clientHeight || 460;
    const dpr = window.devicePixelRatio || 1;
    const changed = nextWidth !== width || nextHeight !== height;
    width = nextWidth;
    height = nextHeight;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.getContext("2d")?.setTransform(dpr, 0, 0, dpr, 0, 0);
    if (changed && model.nodes.length) rerun();
    else draw();
  }

  function hit(event: PointerEvent): GraphNode | null {
    const rect = canvas.getBoundingClientRect();
    const x = event.clientX - rect.left;
    const y = event.clientY - rect.top;
    for (let index = model.nodes.length - 1; index >= 0; index -= 1) {
      const node = model.nodes[index];
      if (node && Math.hypot(x - node.x, y - node.y) <= nodeRadius(node) + 5) return node;
    }
    return null;
  }

  function pointerMove(event: PointerEvent): void {
    const node = hit(event);
    const next = node?.id || null;
    if (next === hover) return;
    hover = next;
    canvas.style.cursor = node ? "pointer" : "default";
    draw();
  }

  function selectNode(event: PointerEvent): void {
    onselect?.(hit(event));
  }

  $effect(() => {
    void model;
    if (!mounted || activeModel === model) return;
    activeModel = model;
    rerun();
  });

  $effect(() => {
    void selected;
    if (mounted) draw();
  });

  onMount(() => {
    mounted = true;
    reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    observer = new ResizeObserver(resize);
    observer.observe(canvas);
    activeModel = model;
    resize();
  });

  onDestroy(() => {
    observer?.disconnect();
    if (frame) cancelAnimationFrame(frame);
  });
</script>

<div class="graph-shell">
  <div class="graph-toolbar">
    <span class="meta">{model.nodes.length} nodes / {model.links.length} links</span>
    <span class="state" data-running={status === "running"}>{status}</span>
    <Button variant="quiet" size="sm" icon={status === "running" ? "pause" : "play"} armed={model.nodes.length > 0} onclick={togglePause}>
      {status === "running" ? "Pause" : "Resume"}
    </Button>
    <Button variant="quiet" size="sm" icon="refresh" armed={model.nodes.length > 0} onclick={rerun}>Re-run</Button>
  </div>
  <canvas
    bind:this={canvas}
    class="graph"
    aria-label="Memory relationship graph"
    onpointermove={pointerMove}
    onpointerleave={() => { hover = null; draw(); }}
    onpointerup={selectNode}
  ></canvas>
</div>

<style>
  .graph-shell { min-width: 0; }
  .graph-toolbar { display: flex; align-items: center; gap: var(--s2); min-height: 42px; padding: 0 var(--s2) 0 var(--s4); border-bottom: 1px solid var(--line-soft); }
  .meta { margin-right: auto; font-family: var(--mono); font-size: var(--f-micro); color: var(--ink-faint); }
  .state { display: inline-flex; align-items: center; gap: var(--s2); color: var(--ink-faint); font-size: var(--f-small); }
  .state::before { content: ""; width: 5px; height: 5px; border-radius: 50%; background: var(--ink-faint); }
  .state[data-running="true"]::before { background: var(--ink); animation: breathe 1.2s var(--ease) infinite alternate; }
  .graph { width: 100%; height: clamp(390px, 48vh, 520px); touch-action: none; }
  @keyframes breathe { to { opacity: 0.35; } }
  @media (prefers-reduced-motion: reduce) { .state[data-running="true"]::before { animation: none; } }
  @media (max-width: 680px) {
    .graph-toolbar { flex-wrap: wrap; padding-block: var(--s2); }
    .meta { flex-basis: 100%; }
    .graph { height: 400px; }
  }
</style>
