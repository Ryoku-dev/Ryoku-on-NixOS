<script lang="ts">
  import { onMount } from "svelte";
  import type { Wallpaper } from "$lib/state/theme.svelte";
  import type { Vitals } from "./types";
  import { formatUptime } from "./types";

  interface Props {
    wallpaper: Wallpaper | null;
    vitals: Vitals | null;
  }

  let { wallpaper, vitals }: Props = $props();
  let now = $state(new Date());
  let mediaReady = $state(false);
  let visible = $state(true);
  let video: HTMLVideoElement | undefined = $state();

  const time = $derived(new Intl.DateTimeFormat(undefined, { hour: "numeric", minute: "2-digit" }).format(now));
  const date = $derived(new Intl.DateTimeFormat(undefined, { weekday: "long", month: "long", day: "numeric" }).format(now));
  const wallpaperURL = $derived(wallpaper ? `/api/wallpaper?rev=${encodeURIComponent(wallpaper.rev)}` : "");

  $effect(() => {
    wallpaperURL;
    mediaReady = false;
  });

  $effect(() => {
    if (!video) return;
    if (visible && wallpaper?.kind === "video") void video.play().catch(() => undefined);
    else video.pause();
  });

  onMount(() => {
    visible = !document.hidden;
    const clock = window.setInterval(() => (now = new Date()), 1000);
    const onVisibility = () => (visible = !document.hidden);
    document.addEventListener("visibilitychange", onVisibility);
    return () => {
      clearInterval(clock);
      document.removeEventListener("visibilitychange", onVisibility);
      video?.pause();
    };
  });
</script>

<section class="hero" class:has-art={wallpaper && mediaReady} aria-label="This machine">
  <div class="art" aria-hidden="true">
    {#if wallpaper?.kind === "video"}
      <video
        bind:this={video}
        src={wallpaperURL}
        muted
        loop
        playsinline
        preload="metadata"
        onloadeddata={() => (mediaReady = true)}
        onerror={() => (mediaReady = false)}
      ></video>
    {:else if wallpaper}
      <img src={wallpaperURL} alt="" onload={() => (mediaReady = true)} onerror={() => (mediaReady = false)} />
    {/if}
  </div>

  <div class="readout">
    <p class="machine-line">
      <span class="seal t-jp" aria-hidden="true">力</span>
      <span>{vitals?.host || "ryoku"}</span>
      <span>{vitals?.kernel || "waiting for the machine"}</span>
    </p>
    <h1 class="clock" aria-label={`Local time ${time}`}>{time}</h1>
    <p class="date">{date}</p>
    <p class="uptime">Up <strong>{vitals ? formatUptime(vitals.uptime) : "—"}</strong></p>
  </div>
</section>

<style>
  .hero {
    position: relative;
    min-height: clamp(300px, 40vh, 430px);
    overflow: hidden;
    isolation: isolate;
    background: var(--paper-lift);
    border-bottom: 1px solid var(--line-soft);
  }
  .art { position: absolute; inset: 0; z-index: -2; }
  .art img, .art video {
    width: 100%;
    height: 100%;
    object-fit: cover;
    opacity: 0;
    transform: scale(1.015);
    animation: art-in var(--t-slow) var(--ease-out) forwards;
  }
  @keyframes art-in { to { opacity: 1; transform: scale(1); } }
  .hero::after {
    content: "";
    position: absolute;
    inset: 0;
    z-index: -1;
    background: linear-gradient(90deg, var(--paper) 0%, color-mix(in srgb, var(--paper) 90%, transparent) 38%, color-mix(in srgb, var(--paper) 32%, transparent) 74%, color-mix(in srgb, var(--paper) 12%, transparent) 100%);
  }
  .hero:not(.has-art)::after { background: none; }
  .readout {
    display: flex;
    flex-direction: column;
    justify-content: center;
    min-height: inherit;
    width: min(100%, 740px);
    padding: var(--s6) var(--s7);
  }
  .machine-line {
    display: flex;
    align-items: center;
    gap: var(--s3);
    margin-bottom: var(--s5);
    color: var(--ink-dim);
    font-family: var(--mono);
    font-size: var(--f-micro);
    letter-spacing: var(--track-label);
    text-transform: uppercase;
  }
  .machine-line span + span::before { content: "/"; margin-right: var(--s3); color: var(--ink-faint); }
  .machine-line .seal { color: var(--alert); font-size: 14px; font-weight: 700; letter-spacing: 0; }
  .machine-line .seal + span::before { content: none; }
  .clock {
    width: max-content;
    font-family: var(--display);
    font-size: clamp(68px, 9vw, 126px);
    font-weight: 300;
    line-height: .82;
    letter-spacing: -.055em;
    color: var(--ink);
    font-variant-numeric: tabular-nums;
    animation: numeral-in 760ms var(--ease-out) both;
  }
  .date {
    margin-top: var(--s4);
    font-size: var(--f-row);
    color: var(--ink-dim);
    animation: numeral-in 760ms 100ms var(--ease-out) both;
  }
  @keyframes numeral-in { from { opacity: 0; transform: translateY(8px); } }
  .uptime { margin-top: var(--s2); color: var(--ink-mute); font-size: var(--f-small); }
  .uptime strong { color: var(--ink); font-weight: 500; }
  @media (max-width: 680px) {
    .hero { min-height: 280px; }
    .readout { padding: var(--s6) var(--s5); }
    .clock { font-size: clamp(58px, 20vw, 84px); }
    .machine-line span:last-child { display: none; }
  }
</style>
