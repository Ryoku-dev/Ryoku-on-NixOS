<script lang="ts">
  import { onMount } from "svelte";
  import Page from "$lib/app/Page.svelte";
  import { router } from "$lib/app/router.svelte";
  import { api } from "$lib/api/client";
  import Markdown from "$lib/content/Markdown.svelte";
  import VaultTree from "$lib/pages/vault/VaultTree.svelte";
  import { groupVaultFiles, type VaultFile } from "$lib/pages/vault/tree";
  import Button from "$lib/ui/Button.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import Field from "$lib/ui/Field.svelte";

  interface VaultResponse {
    root: string;
    files: VaultFile[];
  }

  let vault = $state<VaultResponse | null>(null);
  let document = $state("");
  let current = $state<string | null>(null);
  let filter = $state("");
  let loading = $state(true);
  let documentLoading = $state(false);
  let error = $state("");
  let missing = $state("");
  let reindexing = $state(false);
  let reindexLabel = $state("Reindex");
  let copyLabel = $state("Copy path");
  let request = 0;

  const groups = $derived(groupVaultFiles(vault?.files || []));
  const routePath = $derived(router.rest.join("/"));
  const absolutePath = $derived(current && vault ? `${vault.root.replace(/\/$/, "")}/${current}` : "");

  async function openDocument(path: string): Promise<void> {
    current = path;
    missing = "";
    document = "";
    documentLoading = true;
    const turn = ++request;
    try {
      const source = await api.vaultFile(path);
      if (turn !== request) return;
      document = source;
      localStorage.setItem("rashin.vault.last", path);
    } catch {
      if (turn !== request) return;
      missing = path;
    } finally {
      if (turn === request) documentLoading = false;
    }
  }

  function chooseFile(path: string): void {
    router.go("vault", ...path.split("/"));
  }

  async function loadVault(preferred = ""): Promise<void> {
    loading = true;
    error = "";
    try {
      const response = await api.vault() as unknown as VaultResponse;
      vault = response;
      const files = response.files || [];
      if (!files.length) {
        current = null;
        document = "";
        return;
      }
      if (preferred) {
        if (files.some((file) => file.path === preferred)) await openDocument(preferred);
        else {
          current = preferred;
          missing = preferred;
        }
        return;
      }
      const remembered = localStorage.getItem("rashin.vault.last") || "";
      const fallback = files.find((file) => file.path === remembered)?.path
        || files.find((file) => file.path === "desktop.md")?.path
        || files[0]!.path;
      chooseFile(fallback);
      if (routePath === fallback) await openDocument(fallback);
    } catch {
      error = "The vault is out of reach. Start the Rashin daemon, then try again.";
    } finally {
      loading = false;
    }
  }

  async function reindex(): Promise<void> {
    reindexing = true;
    reindexLabel = "Indexing…";
    try {
      await api.reindex();
      await loadVault(current || routePath);
      reindexLabel = "Reindexed";
      setTimeout(() => reindexLabel = "Reindex", 1800);
    } catch {
      reindexLabel = "Reindex failed";
      setTimeout(() => reindexLabel = "Reindex", 2200);
    } finally {
      reindexing = false;
    }
  }

  async function copyPath(): Promise<void> {
    if (!absolutePath) return;
    try {
      await navigator.clipboard.writeText(absolutePath);
      copyLabel = "Copied";
    } catch {
      copyLabel = "Copy failed";
    }
    setTimeout(() => copyLabel = "Copy path", 1400);
  }

  $effect(() => {
    const path = routePath;
    if (!vault || !path || path === current) return;
    if (vault.files.some((file) => file.path === path)) void openDocument(path);
    else {
      current = path;
      document = "";
      missing = path;
    }
  });

  onMount(() => {
    void loadVault(routePath);
  });
</script>

{#snippet tools()}
  <Button icon="refresh" size="sm" busy={reindexing} onclick={reindex}>{reindexLabel}</Button>
{/snippet}

<Page title="Vault" gloss="書庫" lead="The machine’s durable maps, memory and journal." {tools}>
  {#if loading}
    <div class="loading t-small">Reading the vault…</div>
  {:else if error}
    <Empty icon="book" title="Vault unavailable" body={error} />
  {:else if !vault?.files.length}
    <Empty icon="book" title="The vault is empty" body="Run Reindex to build the machine maps and begin the journal." />
  {:else}
    <div class="vault-layout">
      <aside class="vault-side">
        <Field label="Filter files" placeholder="Name" bind:value={filter} />
        <div class="tree-scroll">
          <VaultTree {groups} {current} {filter} onopen={chooseFile} />
        </div>
      </aside>

      <article class="reader">
        {#if current}
          <header class="pathbar">
            <span class="path" title={absolutePath}>{absolutePath}</span>
            <Button variant="quiet" size="sm" icon="copy" onclick={copyPath}>{copyLabel}</Button>
          </header>
        {/if}
        <div class="document-scroll">
          {#if documentLoading}
            <p class="reader-note">Opening {current}…</p>
          {:else if missing}
            <Empty icon="file" title="Document not found" body={`${missing} is not in this vault. Choose another file or reindex.`} />
          {:else if document}
            <Markdown source={document} class="vault-doc" />
          {:else}
            <Empty icon="file" title="Choose a document" body="Select a map, memory note or journal entry from the tree." />
          {/if}
        </div>
      </article>
    </div>
  {/if}
</Page>

<style>
  .loading { padding: var(--s5) 0; color: var(--ink-mute); }
  .vault-layout {
    display: grid;
    grid-template-columns: minmax(248px, 292px) minmax(0, 1fr);
    height: calc(100vh - 216px);
    min-height: 480px;
    border: 1px solid var(--line-soft);
    border-radius: var(--radius);
    overflow: hidden;
  }
  .vault-side { display: flex; flex-direction: column; gap: var(--s4); min-height: 0; padding: var(--s4); border-right: 1px solid var(--line); background: var(--paper-lift); }
  .tree-scroll { min-height: 0; overflow: auto; padding-right: var(--s1); }
  .reader { display: flex; flex-direction: column; min-width: 0; min-height: 0; background: var(--paper); }
  .pathbar {
    position: sticky;
    top: 0;
    z-index: 1;
    display: flex;
    align-items: center;
    gap: var(--s3);
    min-height: 46px;
    padding: 0 var(--s4) 0 var(--s5);
    border-bottom: 1px solid var(--line-soft);
    background: var(--paper);
  }
  .path { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; font-family: var(--mono); font-size: var(--f-small); color: var(--ink-mute); }
  .document-scroll { flex: 1; min-height: 0; overflow: auto; padding: var(--s6) clamp(var(--s5), 4vw, var(--s7)) var(--s7); }
  .reader-note { color: var(--ink-mute); font-size: var(--f-small); }
  :global(.vault-doc.prose) { max-width: 74ch; font-size: var(--f-row); line-height: 1.7; }
  :global(.vault-doc.prose h1) { font-family: var(--display); font-size: 28px; font-weight: 400; line-height: 1.2; }
  :global(.vault-doc.prose h2) { font-family: var(--display); font-size: 21px; font-weight: 400; line-height: 1.2; }
  :global(.vault-doc.prose h2::before) { content: "// "; color: var(--ink-faint); }
  :global(.vault-doc.prose h3) { font-size: 17px; }
  :global(.vault-doc.prose pre) { padding: var(--s4); background: var(--paper); }
  :global(.vault-doc.prose table) { width: 100%; font-size: var(--f-small); }
  :global(.vault-doc.prose th) { font-family: var(--mono); font-size: var(--f-micro); font-weight: 400; letter-spacing: var(--track-label); text-transform: uppercase; color: var(--ink-faint); }
  :global(.vault-doc.prose blockquote) { font-family: var(--display); font-size: 17px; font-style: italic; }

  @media (max-width: 900px) {
    .vault-layout { grid-template-columns: 1fr; height: auto; min-height: 0; overflow: visible; }
    .vault-side { max-height: 360px; border-right: 0; border-bottom: 1px solid var(--line); }
    .reader { min-height: 520px; }
  }
</style>
