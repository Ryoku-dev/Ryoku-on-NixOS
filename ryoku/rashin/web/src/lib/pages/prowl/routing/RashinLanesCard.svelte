<script lang="ts">
  import type { QuickResponse } from "$lib/api/client";
  import { ryoku } from "$lib/chat/store.svelte";
  import Card from "$lib/ui/Card.svelte";
  import Chip from "$lib/ui/Chip.svelte";
  import Empty from "$lib/ui/Empty.svelte";
  import Select from "$lib/ui/Select.svelte";

  interface Props {
    quick: QuickResponse | null;
    busy?: boolean;
    error?: string;
    onset: (route: string) => void;
  }

  let { quick, busy = false, error = "", onset }: Props = $props();
  const quickOptions = $derived((quick?.routes ?? [])
    .map((route) => ({ value: route.id, label: route.label, hint: route.sub }))
    .sort((left, right) => Number(right.value === "agent") - Number(left.value === "agent")));
  const agentOptions = $derived.by(() => {
    const options = ryoku.state.models.map((model) => ({
      value: model.id,
      label: model.id === ryoku.state.pick ? `${model.name} · picked` : model.name,
      hint: model.description || model.id,
    }));
    if (ryoku.state.pick && !ryoku.state.models.some((model) => model.id === ryoku.state.pick)) {
      options.unshift({
        value: ryoku.state.pick,
        label: `${ryoku.state.pick} · picked`,
        hint: ryoku.state.pickUnavailable ? "Not available in this session" : "Picked for this harness",
      });
    }
    return options;
  });
  const agentSelected = $derived(ryoku.state.pick || ryoku.state.currentModel);
  const agentModel = $derived(ryoku.state.models.find((model) => model.id === ryoku.state.currentModel));
  const pickedAgentModel = $derived(ryoku.state.models.find((model) => model.id === ryoku.state.pick));
</script>

<Card title="Rashin lanes" gloss="羅針" lead="Choose Ask's route and the model pick shared by Agent sessions.">
  <div class="lanes">
    <section class="lane">
      <header>
        <div>
          <span class="t-label">Ask route</span>
          <h3>{quick?.label || "Route unavailable"}</h3>
        </div>
        <Chip tone={quick?.ready ? "plate" : "alert"}>{quick?.ready ? "Ready" : "Not ready"}</Chip>
      </header>
      {#if error}
        <Empty title="Ask route state is unavailable" body="Start the Rashin service, then return here to choose an Ask route." />
      {:else if quick}
        <p>{quick.ready ? "Ask uses the Agent model or a selected Prowl route." : (quick.reason || "Choose the Agent model or connect a routable Prowl provider.")}</p>
        <dl>
          <div><dt>Gateway</dt><dd>{quick.gateway.running ? quick.gateway.url : "Not required for Agent"}</dd></div>
          <div><dt>Route</dt><dd>{quick.route}</dd></div>
        </dl>
        <Select label="Ask route" options={quickOptions} value={quick.route} placeholder="Choose route" disabled={busy} onchange={onset} />
      {/if}
    </section>

    <section class="lane">
      <header>
        <div>
          <span class="t-label">Agent model</span>
          <h3>{ryoku.state.pick ? pickedAgentModel?.name || ryoku.state.pick : agentModel?.name || ryoku.state.currentModel || "Agent default"}</h3>
        </div>
        <Chip tone={ryoku.state.pickUnavailable ? "alert" : ryoku.connected ? "line" : "quiet"}>
          {ryoku.state.pickUnavailable ? "Pick unavailable" : ryoku.connected ? "Connected" : "Connecting"}
        </Chip>
      </header>
      {#if agentOptions.length === 0}
        <Empty title="Waiting for Agent models" body="Open Agent or wait for the active harness to finish starting." />
      {:else}
        <p>{agentModel?.description || "This explicit pick is applied to every session opened by the active harness."}</p>
        {#if ryoku.state.pickUnavailable}
          <p class="pick-unavailable">Your pick, {ryoku.state.pick}, is not available in this session. Agent kept {ryoku.state.currentModel || "its current model"}.</p>
        {/if}
        <dl>
          <div><dt>Harness</dt><dd>{ryoku.state.agent || "Starting"}</dd></div>
          <div><dt>Pick</dt><dd>{ryoku.state.pick || "Harness default"}</dd></div>
        </dl>
        <Select
          label="Agent model"
          options={agentOptions}
          value={agentSelected}
          placeholder="Choose model"
          disabled={!ryoku.connected}
          onchange={(id) => ryoku.setModel(id)}
        />
      {/if}
    </section>
  </div>
</Card>

<style>
  .lanes { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: var(--s5); }
  .lane { min-width: 0; }
  .lane + .lane { padding-left: var(--s5); border-left: 1px solid var(--line-soft); }
  header { display: flex; align-items: flex-start; justify-content: space-between; gap: var(--s3); }
  header > div { min-width: 0; }
  h3 { margin-top: var(--s1); overflow: hidden; color: var(--ink); font-family: var(--display); font-size: 24px; font-weight: 400; line-height: 1.2; text-overflow: ellipsis; white-space: nowrap; }
  .lane > p { min-height: 42px; margin-top: var(--s2); color: var(--ink-mute); font-size: var(--f-small); line-height: 1.5; }
  .lane > .pick-unavailable { min-height: 0; padding: var(--s3); border: 1px solid color-mix(in srgb, var(--alert) 45%, transparent); border-radius: var(--radius); color: var(--alert); }
  dl { display: grid; gap: var(--s2); margin: var(--s4) 0; padding-top: var(--s3); border-top: 1px solid var(--line-soft); }
  dl div { display: grid; grid-template-columns: 72px minmax(0, 1fr); gap: var(--s3); }
  dt { color: var(--ink-faint); font-size: var(--f-small); }
  dd { margin: 0; overflow: hidden; color: var(--ink-dim); font-family: var(--mono); font-size: var(--f-micro); text-overflow: ellipsis; white-space: nowrap; }
  @media (max-width: 1100px) {
    .lanes { grid-template-columns: 1fr; }
    .lane + .lane { padding: var(--s5) 0 0; border-left: 0; border-top: 1px solid var(--line-soft); }
  }
</style>
