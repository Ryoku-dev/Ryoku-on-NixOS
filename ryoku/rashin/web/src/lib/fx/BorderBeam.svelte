<!-- A beam of light riding the border of whatever this sits inside. The host
     is an absolutely placed, pointer-transparent overlay, so the parent only
     needs `position: relative`; the library's wrapper fills it and its ::after
     stroke rides the parent's edge. `line` is the composer's bottom-only glow
     while the agent works; `md` is a full ring. -->
<script lang="ts">
  import { BorderBeam, type BorderBeamProps } from "border-beam";
  import { mountIsland, type Island } from "./island";
  import { createElement } from "react";

  interface Props {
    active?: boolean;
    size?: BorderBeamProps["size"];
    colorVariant?: BorderBeamProps["colorVariant"];
    strength?: number;
    radius?: number;
    duration?: number;
    light?: boolean;
  }

  let { active = true, size = "md", colorVariant = "mono", strength = 0.9, radius, duration, light = false }: Props = $props();

  let host: HTMLDivElement | undefined = $state();
  let island: Island<BorderBeamProps> | null = null;

  $effect(() => {
    if (!host) return;
    island = mountIsland<BorderBeamProps>(host, BorderBeam);
    return () => {
      island?.destroy();
      island = null;
    };
  });

  $effect(() => {
    if (!island) return;
    const r = radius ?? (parseFloat(getComputedStyle(host!.parentElement ?? host!).borderRadius) || 6);
    island.render({
      active,
      size,
      colorVariant,
      strength,
      theme: light ? "light" : "dark",
      borderRadius: r,
      duration,
      style: { position: "absolute", inset: 0, borderRadius: r },
      children: createElement("div", { style: { width: "100%", height: "100%", borderRadius: r } }),
    });
  });
</script>

<div class="beam" bind:this={host} aria-hidden="true"></div>

<style>
  .beam {
    position: absolute;
    inset: 0;
    pointer-events: none;
    z-index: 1;
  }
</style>
