<!-- A thought orb driven by thinking-orbs' engine exports (its documented
     non-React surface): the preset resolves a state and size to a mode, the
     mode paints a frame on a plain 2D canvas, and this component owns the
     clock. Monochrome, so it is ink on paper like everything else. -->
<script lang="ts">
  import { MODE_FRAMES, paintFrame, resolvePreset, type OrbSize, type OrbState } from "thinking-orbs/engine";

  interface Props {
    mode?: OrbState;
    size?: OrbSize;
    speed?: number;
    paused?: boolean;
    light?: boolean;
    label?: string;
  }

  let { mode = "breathing", size = 20, speed = 1, paused = false, light = false, label }: Props = $props();

  let canvas: HTMLCanvasElement | undefined = $state();

  const LABELS: Record<string, string> = {
    working: "Working",
    searching: "Searching",
    solving: "Solving",
    listening: "Listening",
    connecting: "Connecting",
    weaving: "Weaving",
    composing: "Composing",
    breathing: "Thinking",
    shaping: "Shaping",
  };

  $effect(() => {
    if (!canvas) return;
    const el = canvas;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    el.width = Math.round(size * dpr);
    el.height = Math.round(size * dpr);
    const ctx = el.getContext("2d");
    if (!ctx) return;
    const { mode: key, speed: baseSpeed, opts } = resolvePreset(mode, size);
    const frameFn = MODE_FRAMES[key];
    const effSpeed = baseSpeed * speed;
    const dark = !light;
    const frame = (tSec: number) => {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, size, size);
      paintFrame(ctx, frameFn(size, tSec, opts), dark);
    };
    const reduced = matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduced || paused) {
      frame(0.6);
      return;
    }
    let raf = 0;
    let running = false;
    const loop = () => {
      frame((performance.now() / 1000) * effSpeed);
      if (running) raf = requestAnimationFrame(loop);
    };
    const start = () => {
      if (running) return;
      running = true;
      raf = requestAnimationFrame(loop);
    };
    const stop = () => {
      running = false;
      cancelAnimationFrame(raf);
    };
    frame((performance.now() / 1000) * effSpeed);
    let visible = true;
    const io = new IntersectionObserver(([entry]) => {
      visible = entry?.isIntersecting ?? true;
      if (visible && document.visibilityState !== "hidden") start();
      else stop();
    });
    io.observe(el);
    const onVis = () => {
      if (document.visibilityState === "hidden") stop();
      else if (visible) start();
    };
    document.addEventListener("visibilitychange", onVis);
    return () => {
      stop();
      io.disconnect();
      document.removeEventListener("visibilitychange", onVis);
    };
  });
</script>

<canvas
  bind:this={canvas}
  class="orb"
  aria-label={label ?? LABELS[mode]}
  style:width="{size}px"
  style:height="{size}px"
></canvas>

<style>
  .orb {
    display: block;
    flex: none;
  }
</style>
