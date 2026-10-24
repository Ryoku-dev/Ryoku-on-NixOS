<script lang="ts">
  import Chip from "$lib/ui/Chip.svelte";
  import Icon from "$lib/ui/Icon.svelte";
  import { flattenVaultGroup, humanBytes, type VaultGroup } from "./tree";

  interface Props {
    groups: VaultGroup[];
    current: string | null;
    filter: string;
    onopen: (path: string) => void;
  }

  let { groups, current, filter, onopen }: Props = $props();
  let groupState = $state<Record<string, boolean>>({ wiki: true, maps: true, memory: true, journal: true, source: false, other: true });
  let folderState = $state<Record<string, boolean>>({});
  let journalExpanded = $state(false);
  const openFolders = $derived(new Set(Object.keys(folderState).filter((key) => folderState[key])));

  function toggleGroup(key: string): void {
    groupState[key] = !groupState[key];
  }

  function toggleFolder(key: string): void {
    folderState[key] = !folderState[key];
  }
</script>

<div class="tree" aria-label="Vault files">
  {#each groups as group (group.key)}
    {@const rows = flattenVaultGroup(group, openFolders, filter, journalExpanded)}
    {@const groupOpen = Boolean(filter.trim()) || groupState[group.key]}
    {#if !filter.trim() || rows.length}
      <section class="group">
        <button class="group-head" type="button" aria-expanded={groupOpen} onclick={() => toggleGroup(group.key)}>
          <span class:open={groupOpen} class="chevron"><Icon name="chevronRight" size={13} /></span>
          <span>{group.label}</span>
          <span class="count">{filter.trim() ? rows.filter((row) => row.kind === "file").length : group.files.length}</span>
        </button>
        {#if groupOpen}
          <div class="group-items">
            {#each rows as row (row.key)}
              {#if row.kind === "folder"}
                <button
                  class="folder"
                  style:padding-left={`calc(var(--s3) + ${row.depth} * var(--s3))`}
                  type="button"
                  aria-expanded={row.open}
                  onclick={() => toggleFolder(row.key)}
                >
                  <span class:open={row.open} class="chevron"><Icon name="chevronRight" size={12} /></span>
                  <Icon name="folder" size={13} />
                  <span class="name">{row.name}</span>
                </button>
              {:else if row.file}
                <button
                  class="file plate"
                  class:on={current === row.file.path}
                  style:padding-left={`calc(var(--s3) + ${row.depth} * var(--s3))`}
                  type="button"
                  aria-current={current === row.file.path ? "page" : undefined}
                  title={row.file.path}
                  onclick={() => onopen(row.file!.path)}
                >
                  <Icon name="file" size={13} />
                  <span class="name">{row.name}</span>
                  {#if row.file.generated}<Chip mono>gen</Chip>{/if}
                  <span class="size">{humanBytes(row.file.size)}</span>
                </button>
              {/if}
            {/each}
            {#if group.key === "journal" && group.files.length > 8 && !filter.trim()}
              <button class="more" type="button" onclick={() => journalExpanded = !journalExpanded}>
                {journalExpanded ? "Show recent" : `Show all ${group.files.length}`}
              </button>
            {/if}
          </div>
        {/if}
      </section>
    {/if}
  {/each}
</div>

<style>
  .tree { display: flex; flex-direction: column; gap: var(--s1); }
  .group { min-width: 0; }
  .group-head, .folder {
    display: flex;
    align-items: center;
    gap: var(--s2);
    width: 100%;
    min-height: 34px;
    border-radius: var(--radius);
    color: var(--ink-mute);
    text-align: left;
    transition: color var(--t-fast) var(--ease), background-color var(--t-fast) var(--ease);
  }
  .group-head { padding: 0 var(--s2); font-family: var(--mono); font-size: var(--f-micro); letter-spacing: var(--track-label); text-transform: uppercase; }
  .group-head:hover, .folder:hover { color: var(--ink); background: var(--tint5); }
  .count { margin-left: auto; color: var(--ink-faint); letter-spacing: 0; }
  .chevron { display: inline-flex; flex: none; transition: transform var(--t-fast) var(--ease-out); }
  .chevron.open { transform: rotate(90deg); }
  .group-items { display: flex; flex-direction: column; gap: 2px; animation: reveal var(--t-mid) var(--ease-out); }
  .folder { padding-right: var(--s2); font-size: var(--f-small); }
  .file {
    display: flex;
    align-items: center;
    width: 100%;
    min-height: 34px;
    padding-right: var(--s2);
    gap: var(--s2);
    border-radius: var(--radius);
    color: var(--ink-dim);
    text-align: left;
    transition: background-color var(--t-fast) var(--ease), color var(--t-fast) var(--ease);
  }
  .file:hover { background: var(--tint5); color: var(--ink); }
  .file.on { background: var(--bone); color: var(--ink-on-bone); }
  .name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .file .name { flex: 1; min-width: 0; }
  .size { flex: none; font-family: var(--mono); font-size: var(--f-tiny); color: var(--ink-faint); }
  :global(.file.on .chip) { color: color-mix(in srgb, var(--ink-on-bone) 68%, transparent); border-color: color-mix(in srgb, var(--ink-on-bone) 34%, transparent); }
  .file.on .size { color: color-mix(in srgb, var(--ink-on-bone) 62%, transparent); }
  .more { margin: var(--s1) 0 var(--s1) var(--s4); min-height: var(--ctl-h); color: var(--ink-mute); font-size: var(--f-small); }
  .more:hover { color: var(--ink); }
  @keyframes reveal { from { opacity: 0; transform: translateY(-2px); } }
</style>
