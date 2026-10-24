<script lang="ts">
  import { onMount } from "svelte";
  import { api } from "$lib/api/client";
  import Page from "$lib/app/Page.svelte";
  import { router } from "$lib/app/router.svelte";
  import Markdown from "$lib/content/Markdown.svelte";
  import type { VaultFile } from "$lib/pages/vault/tree";
  import { wikiFallbackTitle, wikiFiles, wikiPageName, wikiTitle } from "$lib/pages/wiki/pages";
  import Button from "$lib/ui/Button.svelte";
  import Empty from "$lib/ui/Empty.svelte";

  interface VaultResponse {
    files: VaultFile[];
  }

  let files = $state<VaultFile[]>([]);
  let titles = $state<Record<string, string>>({});
  let current = $state("");
  let document = $state("");
  let loading = $state(true);
  let documentLoading = $state(false);
  let error = $state("");
  let missing = $state("");
  let request = 0;

  const routePage = $derived(router.rest[0] || "README");
  const routePath = $derived(`wiki/${routePage}.md`);
  const currentIndex = $derived(files.findIndex((file) => file.path === current));
  const previous = $derived(currentIndex > 0 ? files[currentIndex - 1] : undefined);
  const next = $derived(currentIndex >= 0 && currentIndex < files.length - 1 ? files[currentIndex + 1] : undefined);


  function choose(path: string): void {
    router.go("wiki", wikiPageName(path));
  }

  async function openDocument(path: string): Promise<void> {
    current = path;
    document = "";
    missing = "";
    documentLoading = true;
    const turn = ++request;
    try {
      const source = await api.vaultFile(path);
      if (turn !== request) return;
      document = source;
      titles = { ...titles, [path]: wikiTitle(source, path) };
    } catch {
      if (turn !== request) return;
      missing = path;
    } finally {
      if (turn === request) documentLoading = false;
    }
  }

  async function loadWiki(): Promise<void> {
    loading = true;
    error = "";
    try {
      const response = await api.vault() as unknown as VaultResponse;
      files = wikiFiles(response.files || []);
      if (files.some((file) => file.path === routePath)) await openDocument(routePath);
      else if (files.length) missing = routePath;
    } catch {
      error = "The wiki is out of reach. Start the Rashin daemon, then try again.";
    } finally {
      loading = false;
    }
  }

  $effect(() => {
    const path = routePath;
    if (loading || !files.length || path === current) return;
    if (files.some((file) => file.path === path)) void openDocument(path);
    else {
      current = path;
      document = "";
      missing = path;
    }
  });

  onMount(() => void loadWiki());
</script>

<Page title="Wiki" gloss="手引" lead="A practical guide to building and finding your way around Ryoku.">
  {#if loading}
    <p class="reader-note">Opening the wiki…</p>
  {:else if error}
    <Empty icon="book" title="Wiki unavailable" body={error} />
  {:else if files.length === 0}
    <Empty icon="book" title="The wiki is empty" body="Reindex the vault after the wiki has been installed." />
  {:else}
    <div class="wiki-layout">
      <aside class="wiki-side" aria-label="Wiki pages">
        <span class="t-mark">Pages</span>
        <nav>
          {#each files as file (file.path)}
            <button class:on={file.path === current} type="button" aria-current={file.path === current ? "page" : undefined} onclick={() => choose(file.path)}>
              {titles[file.path] || wikiFallbackTitle(file.path)}
            </button>
          {/each}
        </nav>
      </aside>

      <article class="reader">
        <div class="document-scroll">
          {#if documentLoading}
            <p class="reader-note">Opening {wikiFallbackTitle(current)}…</p>
          {:else if missing}
            <Empty icon="file" title="Page not found" body={`${wikiPageName(missing)} is not in this wiki. Choose another page.`} />
          {:else if document}
            <Markdown source={document} class="wiki-doc" />
          {/if}
        </div>
        {#if document && (previous || next)}
          <footer>
            <span>{#if previous}<Button variant="line" size="sm" icon="chevronLeft" onclick={() => choose(previous.path)}>{titles[previous.path] || wikiFallbackTitle(previous.path)}</Button>{/if}</span>
            <span>{#if next}<Button variant="line" size="sm" icon="chevronRight" onclick={() => choose(next.path)}>{titles[next.path] || wikiFallbackTitle(next.path)}</Button>{/if}</span>
          </footer>
        {/if}
      </article>
    </div>
  {/if}
</Page>

<style>
  .reader-note { color: var(--ink-mute); font-size: var(--f-small); }
  .wiki-layout { display: grid; grid-template-columns: minmax(220px, 268px) minmax(0, 1fr); height: calc(100vh - 216px); min-height: 480px; overflow: hidden; border: 1px solid var(--line-soft); border-radius: var(--radius); }
  .wiki-side { display: flex; min-height: 0; flex-direction: column; gap: var(--s3); padding: var(--s4); border-right: 1px solid var(--line); background: var(--paper-lift); }
  .wiki-side nav { display: flex; min-height: 0; flex-direction: column; gap: 2px; overflow-y: auto; }
  .wiki-side button { min-height: 36px; padding: 0 var(--s3); border-radius: var(--radius); color: var(--ink-dim); font-size: var(--f-small); text-align: left; transition: color var(--t-fast) var(--ease), background-color var(--t-fast) var(--ease); }
  .wiki-side button:hover { color: var(--ink); background: var(--tint5); }
  .wiki-side button.on { color: var(--ink-on-bone); background: var(--bone); }
  .reader { display: flex; min-width: 0; min-height: 0; flex-direction: column; background: var(--paper); }
  .document-scroll { flex: 1; min-height: 0; overflow-y: auto; padding: var(--s6) clamp(var(--s5), 4vw, var(--s7)) var(--s7); }
  footer { display: flex; justify-content: space-between; gap: var(--s4); padding: var(--s3) var(--s5); border-top: 1px solid var(--line-soft); }
  :global(.wiki-doc.prose) { max-width: 74ch; margin: 0 auto; font-size: var(--f-row); line-height: 1.7; }
  :global(.wiki-doc.prose h1) { font-family: var(--display); font-size: 28px; font-weight: 400; line-height: 1.2; }
  :global(.wiki-doc.prose h2) { font-family: var(--display); font-size: 21px; font-weight: 400; line-height: 1.2; }
  :global(.wiki-doc.prose h2::before) { content: "// "; color: var(--ink-faint); }
  :global(.wiki-doc.prose h3) { font-size: 17px; }
  :global(.wiki-doc.prose pre) { padding: var(--s4); background: var(--paper); }
  :global(.wiki-doc.prose table) { width: 100%; font-size: var(--f-small); }
  :global(.wiki-doc.prose th) { color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-micro); font-weight: 400; letter-spacing: var(--track-label); text-transform: uppercase; }
  :global(.wiki-doc.prose blockquote) { font-family: var(--display); font-size: 17px; font-style: italic; }

  @media (max-width: 800px) {
    .wiki-layout { grid-template-columns: 1fr; height: auto; min-height: 0; overflow: visible; }
    .wiki-side { max-height: 280px; border-right: 0; border-bottom: 1px solid var(--line); }
    .reader { min-height: 520px; }
  }
</style>
