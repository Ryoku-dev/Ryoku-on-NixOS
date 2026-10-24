<script lang="ts">
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import Fold from "$lib/ui/Fold.svelte";
  import Icon from "$lib/ui/Icon.svelte";
  import type { Skill, } from "./harnesses";

  interface Category {
    name?: string;
    skills: Skill[];
  }

  interface Props {
    categories: Category[];
    query: string;
    emptyTitle?: string;
  }

  let { categories, query, emptyTitle = "This agent carries no skills" }: Props = $props();
  const total = $derived(categories.reduce((sum, category) => sum + category.skills.length, 0));
</script>

{#if !categories.length}
  <Empty icon="tool" title={query ? "Nothing matches" : emptyTitle} body={query ? "Try a broader name or description." : "Install or wire skills to make them available here."} />
{:else}
  <div class="skill-groups">
    {#each categories as category (`${category.name}-${category.skills.length}`)}
      <section class="skill-group">
        <Fold open={total <= 40 || Boolean(query)}>
          {#snippet summary()}
            <span class="group-summary">
              <span>{category.name || "misc"}</span>
              <span class="group-count">{category.skills.length}</span>
            </span>
          {/snippet}
          <div class="skill-list">
            {#each category.skills as skill (`${skill.origin}-${skill.dir}-${skill.name}`)}
              <div class="skill-row">
                <Fold>
                  {#snippet summary()}
                    <span class="skill-summary">
                      <span class="skill-name">{skill.name || "Unnamed skill"}</span>
                      <Chip mono>{skill.origin || "agent"}</Chip>
                    </span>
                  {/snippet}
                  <div class="skill-detail">
                    <p>{skill.description || "No description supplied."}</p>
                    {#if skill.dir}<code>{skill.dir}</code>{/if}
                    {#if skill.version}<span class="version">Version {skill.version}</span>{/if}
                    {#if skill.source}
                      <a href={skill.source} target="_blank" rel="noreferrer">
                        <Icon name="external" size={13} /> Source
                      </a>
                    {/if}
                  </div>
                </Fold>
              </div>
            {/each}
          </div>
        </Fold>
      </section>
    {/each}
  </div>
{/if}

<style>
  .skill-groups { border: 1px solid var(--line); border-radius: var(--radius); overflow: hidden; }
  .skill-group + .skill-group { border-top: 1px solid var(--line); }
  .skill-group :global(> .fold > .fold-head) { min-height: var(--row-h); padding: 0 var(--s4); color: var(--ink); }
  .group-summary { display: flex; align-items: center; width: 100%; font-family: var(--mono); font-size: var(--f-small); letter-spacing: var(--track-label); text-transform: uppercase; }
  .group-summary > span:first-child::before { content: "// "; color: var(--ink-faint); }
  .group-count { margin-left: auto; color: var(--ink-faint); letter-spacing: 0; }
  .skill-list { border-top: 1px solid var(--line-soft); }
  .skill-row + .skill-row { border-top: 1px solid var(--line-soft); }
  .skill-row :global(.fold-head) { min-height: 44px; padding: var(--s2) var(--s4); }
  .skill-summary { display: flex; align-items: center; gap: var(--s3); width: 100%; }
  .skill-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; color: var(--ink); font-size: var(--f-body); font-weight: 500; }
  .skill-detail { display: grid; grid-template-columns: minmax(0, 1fr) auto; gap: var(--s2) var(--s4); padding: 0 var(--s5) var(--s4) 42px; }
  .skill-detail p { grid-column: 1 / -1; max-width: 78ch; color: var(--ink-mute); font-size: var(--f-small); }
  .skill-detail code { min-width: 0; overflow-wrap: anywhere; color: var(--ink-faint); font-size: var(--f-small); }
  .skill-detail a { display: inline-flex; align-items: center; gap: var(--s1); color: var(--ink); font-size: var(--f-small); border-bottom: 1px solid var(--line-strong); }
  .version { color: var(--ink-faint); font-size: var(--f-small); }
  @media (max-width: 620px) {
    .skill-detail { grid-template-columns: 1fr; padding-left: var(--s4); }
  }
</style>
