<script lang="ts">
  import type { ToolDiff } from "$lib/chat/protocol";
  import { createUnifiedDiff } from "./diff";

  interface Props {
    diffs: ToolDiff[];
  }

  let { diffs }: Props = $props();
  const files = $derived(diffs.map((entry) => ({
    path: entry.path || "Untitled file",
    diff: createUnifiedDiff(entry.old ?? "", entry.new ?? ""),
  })));
</script>

<div class="diffs" aria-label="File changes">
  {#each files as file (file.path)}
    <section class="diff-file">
      <header class="diff-head">
        <span class="diff-path">{file.path}</span>
        <span class="diff-counts" aria-label={`${file.diff.added} added, ${file.diff.removed} removed`}>
          <span class="added">+{file.diff.added}</span>
          <span class="removed">−{file.diff.removed}</span>
        </span>
      </header>
      {#if file.diff.hunks.length === 0}
        <p class="no-change">No text changes</p>
      {:else}
        <div class="diff-code">
          {#each file.diff.hunks as hunk, index (`${hunk.oldStart}:${hunk.newStart}:${index}`)}
            <div class="hunk-mark">@@ −{hunk.oldStart},{hunk.oldCount} +{hunk.newStart},{hunk.newCount} @@</div>
            {#each hunk.lines as line, lineIndex (lineIndex)}
              <div class="diff-line {line.kind}">
                <span class="line-no">{line.oldNumber ?? ""}</span>
                <span class="line-no">{line.newNumber ?? ""}</span>
                <span class="line-mark" aria-hidden="true">{line.kind === "add" ? "+" : line.kind === "remove" ? "−" : " "}</span>
                <code>{line.text || " "}</code>
              </div>
            {/each}
          {/each}
        </div>
      {/if}
    </section>
  {/each}
</div>

<style>
  .diffs { display: flex; flex-direction: column; gap: var(--s3); }
  .diff-file { overflow: hidden; border: 1px solid var(--line-soft); border-radius: var(--radius); }
  .diff-head {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: var(--s3);
    min-height: 34px;
    padding: var(--s1) var(--s3);
    border-bottom: 1px solid var(--line-soft);
    background: var(--paper-lift);
  }
  .diff-path {
    overflow: hidden;
    color: var(--ink);
    font-family: var(--mono);
    font-size: var(--f-small);
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .diff-counts { display: inline-flex; gap: var(--s2); font-family: var(--mono); font-size: var(--f-micro); }
  .added { color: var(--ink); }
  .removed { color: var(--alert); }
  .diff-code { overflow: auto; font-family: var(--mono); font-size: var(--f-small); line-height: 1.55; }
  .hunk-mark { padding: var(--s1) var(--s3); border-bottom: 1px solid var(--line-soft); color: var(--ink-faint); }
  .diff-line { display: grid; grid-template-columns: 4ch 4ch 2ch minmax(max-content, 1fr); min-height: 22px; }
  .diff-line.add { background: var(--tint10); }
  .diff-line.remove { background: color-mix(in srgb, var(--alert) 11%, transparent); }
  .line-no { padding: 1px var(--s2); border-right: 1px solid var(--line-soft); color: var(--ink-faint); text-align: right; user-select: none; }
  .line-mark { padding: 1px 0 1px var(--s2); color: var(--ink-faint); user-select: none; }
  .add .line-mark { color: var(--ink); }
  .remove .line-mark { color: var(--alert); }
  code { padding: 1px var(--s3) 1px var(--s1); color: var(--ink-dim); white-space: pre; }
  .no-change { padding: var(--s3); color: var(--ink-mute); font-size: var(--f-small); }
</style>
