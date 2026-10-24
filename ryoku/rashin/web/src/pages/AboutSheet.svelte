<script lang="ts">
  import Page from "$lib/app/Page.svelte";
  import { api } from "$lib/api/client";
  import AboutDetails from "$lib/pages/about/AboutDetails.svelte";
  import ShortcutsCard from "$lib/pages/about/ShortcutsCard.svelte";
  import type { AboutInfo, AboutManifest } from "$lib/pages/about/types";

  let about = $state<AboutInfo | null>(null);
  let manifest = $state<AboutManifest | null>(null);
  let error = $state("");

  async function load() {
    const [aboutResult, manifestResult] = await Promise.allSettled([api.about(), api.manifest()]);
    if (aboutResult.status === "fulfilled") {
      about = aboutResult.value as unknown as AboutInfo;
      error = "";
    } else error = "The daemon did not answer.";
    if (manifestResult.status === "fulfilled") manifest = manifestResult.value as unknown as AboutManifest;
  }

  $effect(() => { void load(); });
</script>

<Page title="About" gloss="案内" lead="Build identity, local paths and the few keys worth remembering.">
  <div class="about-layout">
    <AboutDetails {about} {manifest} {error} />
    <ShortcutsCard />
  </div>
</Page>

<style>
  .about-layout { display: grid; gap: var(--s4); align-content: start; }
</style>
