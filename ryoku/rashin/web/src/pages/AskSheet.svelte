<script lang="ts">
  import { onMount } from "svelte";
  import Page from "$lib/app/Page.svelte";
  import { router } from "$lib/app/router.svelte";
  import { api, type QuickResponse } from "$lib/api/client";
  import { ryoku } from "$lib/chat/store.svelte";
  import Markdown from "$lib/content/Markdown.svelte";
  import ThinkingOrb from "$lib/fx/ThinkingOrb.svelte";
  import RecentAsks, { type RecentAsk } from "$lib/pages/ask/RecentAsks.svelte";
  import { readAskStream, type AskAnswer } from "$lib/pages/ask/askstream";
  import Button from "$lib/ui/Button.svelte";
  import Card from "$lib/ui/Card.svelte";
  import Select from "$lib/ui/Select.svelte";

  let question = $state("");
  let activeQuestion = $state("");
  let answer = $state<AskAnswer | null>(null);
  let running = $state(false);
  let working = $state("");
  let error = $state("");
  let generation = 0;
  let recent = $state<RecentAsk[]>([]);
  let recentError = $state("");
  let quick = $state<QuickResponse | null>(null);
  let routeError = $state("");
  let routeBusy = $state(false);
  let copied = $state("");

  const routeOptions = $derived((quick?.routes ?? [])
    .map((route) => ({ value: route.id, label: route.label, hint: route.sub }))
    .sort((left, right) => Number(right.value === "agent") - Number(left.value === "agent")));

  async function loadRecent(): Promise<void> {
    try {
      const data = await api.askRecent() as unknown;
      recent = Array.isArray(data) ? data as RecentAsk[] : [];
      recentError = "";
    } catch {
      recentError = "The daemon did not answer.";
    }
  }

  async function loadRoute(): Promise<void> {
    try {
      quick = await api.quick();
      routeError = "";
    } catch (cause) {
      routeError = cause instanceof Error ? cause.message : "Ask routes are unavailable.";
    }
  }

  async function chooseRoute(route: string): Promise<void> {
    if (!route || routeBusy) return;
    routeBusy = true;
    routeError = "";
    try {
      quick = await api.setQuick(route);
    } catch (cause) {
      routeError = cause instanceof Error ? cause.message : "The Ask route did not change.";
    } finally {
      routeBusy = false;
    }
  }

  async function submit(): Promise<void> {
    const text = question.trim();
    if (!text || running) return;
    const turn = ++generation;
    activeQuestion = text;
    answer = null;
    error = "";
    working = "Starting Ask";
    running = true;
    try {
      const response = await api.ask(text);
      if (!response.body) throw new Error("The daemon returned no answer stream.");
      await readAskStream(response.body, (marker) => {
        if (turn !== generation) return;
        if (marker.kind === "working") working = marker.detail || "Working";
        else if (marker.kind === "answer") {
          answer = marker.answer;
          working = "";
        } else if (marker.kind === "error") {
          error = marker.detail || "Ask stopped before it answered.";
        }
      });
      if (turn === generation && !answer && !error) error = "Ask stopped before it answered.";
      if (turn === generation && answer) await loadRecent();
    } catch (cause) {
      if (turn === generation) error = cause instanceof Error ? cause.message : "The daemon did not answer.";
    } finally {
      if (turn === generation) running = false;
    }
  }

  async function cancel(): Promise<void> {
    if (!running) return;
    ++generation;
    running = false;
    working = "";
    try {
      await api.askCancel();
      error = "Stopped.";
    } catch {
      error = "The stop request did not reach the daemon.";
    }
  }

  function continueWithAgent(id: string, askQuestion: string, askAnswer: string, run: boolean): void {
    const text = askQuestion.trim();
    if (!text) return;
    ryoku.handoff(id, text, askAnswer, run);
    router.go("agent");
  }

  function continueCurrent(): void {
    if (answer) {
      continueWithAgent(answer.id, activeQuestion, answer.text, answer.needsAgent === true);
      return;
    }
    if (running) continueWithAgent("", activeQuestion || question, "", true);
  }

  function selectRecent(ask: RecentAsk): void {
    question = ask.q;
    activeQuestion = ask.q;
    answer = {
      id: ask.id,
      text: ask.a,
      images: ask.images,
      actions: ask.actions,
      via: ask.via,
      needsAgent: ask.needsAgent,
      needsAgentReason: ask.needsAgentReason,
    };
    error = "";
  }

  async function copy(key: string, value: string): Promise<void> {
    try {
      await navigator.clipboard.writeText(value);
      copied = key;
      window.setTimeout(() => {
        if (copied === key) copied = "";
      }, 1_500);
    } catch {
      copied = "";
    }
  }
  function copyCurrentAnswer(): void {
    if (answer) void copy("answer", answer.text);
  }


  function handleKey(event: KeyboardEvent): void {
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      void submit();
    }
  }

  onMount(() => {
    void Promise.all([loadRecent(), loadRoute()]);
  });
</script>

<Page title="Ask" gloss="質問" lead="A quick, read-only answer. Move work to Agent only when you choose to.">
  <div class="ask-grid">
    <section class="ask-main">
      <Card title="Ask Rashin" gloss="問">
        <div class="route-row">
          <div>
            <span class="t-label">Ask route</span>
            <p>{quick?.routes.find((route) => route.id === quick?.route)?.sub || quick?.label || "Loading routes"}</p>
          </div>
          <Select
            size="sm"
            label="Ask route"
            options={routeOptions}
            value={quick?.route ?? ""}
            placeholder="Choose route"
            disabled={routeBusy || routeOptions.length === 0}
            onchange={(route) => void chooseRoute(route)}
          />
        </div>
        {#if routeError}<p class="inline-error" role="alert">{routeError}</p>{/if}

        <div class="ask-field">
          <textarea
            bind:value={question}
            rows="4"
            placeholder="Ask a question about this machine…"
            aria-label="Ask Rashin"
            disabled={running}
            onkeydown={handleKey}
          ></textarea>
          <div class="ask-actions">
            {#if running}
              <Button onclick={() => void cancel()}>Cancel</Button>
            {/if}
            <Button variant="plate" armed={Boolean(question.trim()) && !running} onclick={() => void submit()}>Ask</Button>
          </div>
        </div>

        {#if running}
          <div class="working" aria-live="polite">
            <ThinkingOrb mode="working" size={20} label="Ask is working" />
            <span>{working || "Working"}</span>
            <Button variant="quiet" size="sm" onclick={continueCurrent}>Move to the agent</Button>
          </div>
        {/if}
        {#if error}<p class="inline-error" role="alert">{error}</p>{/if}
      </Card>

      {#if answer}
        <Card>
          <div class="answer-head">
            <div>
              <span class="t-label">Answer</span>
              {#if answer.via}<p class="via">via {answer.via}</p>{/if}
            </div>
          </div>

          {#if answer.needsAgent}
            <div class="needs-agent" role="status">
              <strong>This needs Agent</strong>
              <p>{answer.needsAgentReason || "The read-only Ask lane cannot complete this work."}</p>
            </div>
          {/if}

          <div class="answer-copy"><Markdown source={answer.text} breaks /></div>

          <div class="answer-actions" aria-label="Answer actions">
            <button class="action-chip" type="button" onclick={copyCurrentAnswer}>
              {copied === "answer" ? "Copied" : "Copy answer"}
            </button>
            {#each (answer.actions ?? []) as action, index (`${action.kind}:${action.value}:${index}`)}
              <button class="action-chip" type="button" title={action.value} onclick={() => void copy(`action:${index}`, action.value)}>
                {copied === `action:${index}` ? "Copied" : action.label}
              </button>
            {/each}
          </div>

          <div class="continue-row">
            <Button variant={answer.needsAgent ? "plate" : "line"} onclick={continueCurrent}>
              {answer.needsAgent ? "Move to the agent" : "Continue with the agent"}
            </Button>
          </div>
        </Card>
      {/if}
    </section>

    <aside class="recent-column">
      <RecentAsks
        asks={recent}
        error={recentError}
        onselect={selectRecent}
        oncontinue={(ask) => continueWithAgent(ask.id, ask.q, ask.a, ask.needsAgent === true)}
      />
    </aside>
  </div>
</Page>

<style>
  .ask-grid { display: grid; grid-template-columns: minmax(0, 1fr) minmax(300px, 0.42fr); gap: var(--s5); align-items: start; }
  .ask-main { display: grid; gap: var(--s4); min-width: 0; }
  .route-row, .answer-head, .ask-actions, .working, .continue-row { display: flex; align-items: center; justify-content: space-between; gap: var(--s3); }
  .route-row p, .via { margin-top: var(--s1); color: var(--ink-mute); font-size: var(--f-small); }
  .ask-field { display: grid; gap: var(--s3); margin-top: var(--s4); }
  textarea { width: 100%; min-height: 112px; resize: vertical; padding: var(--s3); border: 1px solid var(--line); border-radius: var(--radius); outline: 0; background: var(--paper-lift); color: var(--ink); font: inherit; line-height: 1.55; }
  textarea:focus { border-color: var(--line-strong); }
  textarea::placeholder { color: var(--ink-faint); }
  .ask-actions { justify-content: flex-end; }
  .working { justify-content: flex-start; margin-top: var(--s4); padding-top: var(--s3); border-top: 1px solid var(--line-soft); color: var(--ink-mute); font-size: var(--f-small); }
  .working :global(.btn:last-child) { margin-left: auto; }
  .inline-error { margin-top: var(--s3); color: var(--alert); font-size: var(--f-small); }
  .answer-head { align-items: flex-start; }
  .needs-agent { margin-top: var(--s4); padding: var(--s3) var(--s4); border: 1px solid color-mix(in srgb, var(--alert) 45%, transparent); border-radius: var(--radius); color: var(--alert); }
  .needs-agent strong { font-weight: 500; }
  .needs-agent p { margin-top: var(--s1); font-size: var(--f-small); }
  .answer-copy { margin-top: var(--s4); }
  .answer-actions { display: flex; flex-wrap: wrap; gap: var(--s2); margin-top: var(--s4); }
  .action-chip { min-height: 26px; max-width: 100%; overflow: hidden; padding: 0 var(--s3); border: 1px solid var(--line); border-radius: 4px; color: var(--ink-dim); font-size: var(--f-small); text-overflow: ellipsis; white-space: nowrap; }
  .action-chip:hover { border-color: var(--line-strong); background: var(--tint5); color: var(--ink); }
  .continue-row { justify-content: flex-end; margin-top: var(--s5); padding-top: var(--s3); border-top: 1px solid var(--line-soft); }
  .recent-column { min-width: 0; padding: var(--s4); border: 1px solid var(--line-soft); border-radius: var(--radius); }
  .recent-column :global(.recent) { padding-top: 0; border-top: 0; }
  @media (max-width: 1050px) {
    .ask-grid { grid-template-columns: 1fr; }
  }
  @media (max-width: 620px) {
    .route-row { align-items: flex-start; flex-direction: column; }
    .route-row :global(.sel) { width: 100%; justify-content: space-between; }
  }
</style>
