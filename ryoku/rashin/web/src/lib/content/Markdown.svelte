<!-- Rendered markdown. Fenced blocks grow a copy affordance after render;
     everything else is the escape-first renderer's trusted output. -->
<script lang="ts">
  import { mdToHtml } from "./markdown";

  interface Props {
    source: string;
    breaks?: boolean;
    class?: string;
  }

  let { source, breaks = false, class: cls = "" }: Props = $props();
  const html = $derived(mdToHtml(source, { breaks }));
  let root: HTMLDivElement | undefined = $state();

  async function copyBlock(pre: HTMLPreElement, btn: HTMLButtonElement) {
    try {
      await navigator.clipboard.writeText(pre.querySelector("code")?.textContent ?? "");
      btn.dataset.done = "1";
      setTimeout(() => delete btn.dataset.done, 1200);
    } catch {
      btn.dataset.done = "";
    }
  }

  $effect(() => {
    void html;
    const el = root;
    if (!el) return;
    for (const pre of el.querySelectorAll<HTMLPreElement>("pre")) {
      if (pre.querySelector(".copy")) continue;
      const btn = document.createElement("button");
      btn.className = "copy";
      btn.type = "button";
      btn.setAttribute("aria-label", "Copy code");
      btn.textContent = "copy";
      btn.addEventListener("click", () => void copyBlock(pre, btn));
      pre.appendChild(btn);
    }
  });
</script>

<div class="prose {cls}" bind:this={root}>{@html html}</div>

<style>
  :global(.prose pre .copy) {
    position: absolute;
    right: var(--s2);
    bottom: var(--s2);
    height: 22px;
    padding: 0 var(--s2);
    border: 1px solid var(--line);
    border-radius: 4px;
    background: var(--paper-lift);
    font-family: var(--mono);
    font-size: var(--f-tiny);
    letter-spacing: var(--track-label);
    text-transform: uppercase;
    color: var(--ink-mute);
    opacity: 0;
    transition: opacity var(--t-fast) var(--ease), color var(--t-fast) var(--ease);
  }
  :global(.prose pre:hover .copy), :global(.prose pre .copy:focus-visible) { opacity: 1; }
  :global(.prose pre .copy[data-done="1"]) { color: var(--ink); border-color: var(--bone); }
</style>
