<!-- The Needle's face: a blobatar seeded by the conversation, so every chat
     has its own creature and the same chat always wears the same one. The
     hue is locked to the accent so it stays a Ryoku surface;
     the shape, eyes and markings come from the seed. Its expression is the
     agent's state, its eyes follow the pointer, and at rest it breathes,
     bobs and glances on blobatar's own idle clock. -->
<script lang="ts">
  import { Blobatar } from "@blobatar/svelte";
  import { gaze } from "@blobatar/svelte/gaze";
  import { happy, idle, sleepy, surprised, thinking, unsure, type Expression } from "blobatar/expression";
  import "blobatar/motion.css";
  import "blobatar/gaze.css";

  export type NeedleMood = "idle" | "thinking" | "working" | "waiting" | "done" | "sleeping" | "failed";

  interface Props {
    /** what the face stands for: a session id, a harness, a provider */
    seed: string;
    mood?: NeedleMood;
    size?: number;
    /** eyes follow the pointer; off for a roster of small faces */
    follow?: boolean;
    /** the idle motion, off for a static roster tile */
    animate?: "always" | "hover" | false;
    label?: string;
  }

  let { seed, mood = "idle", size = 28, follow = true, animate = "always", label }: Props = $props();

  const EXPRESSIONS: Record<NeedleMood, Expression> = {
    idle,
    thinking,
    working: surprised,
    waiting: unsure,
    done: happy,
    sleeping: sleepy,
    failed: unsure,
  };

  // Hue 29 is the accent's own hue (--sun, #e2342a, in OKLCh) and tone 0.7
  // lands the body on the vermillion swatch rather than its pastel tint, so
  // the creature reads as the one accent on the paper; the ink eyes keep
  // their contrast there by blobatar's own guarantee.
  const HUE = 29;
  const TONE = 0.7;

  const eyes = gaze({ travel: 3, target: "pointer" });

  $effect(() => {
    eyes.lookAt(follow && animate ? "pointer" : "rest");
  });
</script>

{#if animate}
  <span class="face" style:width="{size}px" style:height="{size}px" data-mood={mood}>
    <Blobatar
      name={seed || "the needle"}
      {size}
      hue={HUE}
      tone={TONE}
      background={false}
      expression={EXPRESSIONS[mood]}
      {animate}
      title={label}
      {@attach eyes}
    />
  </span>
{:else}
  <span class="face" style:width="{size}px" style:height="{size}px" data-mood={mood}>
    <Blobatar name={seed || "the needle"} {size} hue={HUE} tone={TONE} background={false} expression={EXPRESSIONS[mood]} title={label} />
  </span>
{/if}

<style>
  .face { display: inline-flex; align-items: center; justify-content: center; flex: none; }
  .face :global(svg), .face :global(img) { display: block; overflow: visible; }
  /* A working face leans in; a sleeping one settles. Tiny, so the motion
     reads as a mood and not as a toy. */
  .face[data-mood="working"] :global(svg) { animation: lean 2.4s var(--ease) infinite; }
  .face[data-mood="sleeping"] :global(svg) { transform: translateY(1px) scale(0.96); opacity: 0.8; }
  @keyframes lean { 0%, 100% { transform: rotate(0deg); } 50% { transform: rotate(-4deg) translateY(-1px); } }
  @media (prefers-reduced-motion: reduce) { .face :global(svg) { animation: none; } }
</style>
