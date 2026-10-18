<script lang="ts">
  import { tick } from "svelte";
  import type { ApprovalsMode, CommandInfo, ModelInfo, PromptImage } from "$lib/chat/protocol";
  import type { ChatLane } from "$lib/chat/store.svelte";
  import BorderBeam from "$lib/fx/BorderBeam.svelte";
  import ThinkingOrb from "$lib/fx/ThinkingOrb.svelte";
  import Button from "$lib/ui/Button.svelte";
  import IconButton from "$lib/ui/IconButton.svelte";
  import Seg from "$lib/ui/Seg.svelte";
  import Select from "$lib/ui/Select.svelte";
  import Tooltip from "$lib/ui/Tooltip.svelte";
  import { tokenLabel } from "./presentation";

  interface Props {
    lane: ChatLane;
    draft: string;
    busy: boolean;
    connected: boolean;
    activity: string;
    commands: CommandInfo[];
    models: ModelInfo[];
    currentModel: string;
    agent: string;
    approvals: ApprovalsMode;
    /** an approval is waiting on the person */
    waiting?: boolean;
    usage: { size: number; used: number } | null;
    pick: string;
    pickUnavailable: boolean;
    handoffPending?: boolean;
    focusTarget?: HTMLTextAreaElement;
    ondraft: (value: string) => void;
    onsend: (text: string, images: PromptImage[]) => void;
    oncancel: () => void;
    onmodel: (id: string) => void;
    onapprovals: (mode: ApprovalsMode) => void;

  }

  let {
    lane,
    draft,
    busy,
    connected,
    activity,
    commands,
    models,
    currentModel,
    pick,
    pickUnavailable,
    handoffPending = false,
    agent,
    approvals,
    waiting = false,
    usage,
    focusTarget = $bindable(),
    ondraft,
    onsend,
    oncancel,
    onmodel,
    onapprovals,

  }: Props = $props();

  // The tiers are named by what runs without a prompt; "Read-only" used to
  // read as "the agent may only read" and the first command caught people out.
  const APPROVAL_OPTIONS = [
    { value: "ask", label: "Ask", hint: "Every tool waits for you" },
    { value: "read-only", label: "Reads run", hint: "Reads run; writes and commands wait for you" },
    { value: "auto", label: "All run", hint: "Everything runs; nothing waits for you" },
  ];
  const APPROVAL_HINTS: Record<ApprovalsMode, string> = {
    ask: "Ask: every tool waits for you",
    "read-only": "Reads run: writes and commands still wait for you",
    auto: "All run: writes and commands too; nothing waits for you",
  };

  let filePicker: HTMLInputElement | undefined = $state();
  let images: PromptImage[] = $state([]);
  let commandOpen = $state(false);
  let commandIndex = $state(0);

  const commandMatch = $derived(draft.match(/^\/([^\s]*)$/));
  const commandQuery = $derived(commandMatch ? (commandMatch[1] ?? "").toLowerCase() : null);
  const commandMatches = $derived(commandQuery === null ? [] : commands
    .filter((command) => command.name.toLowerCase().includes(commandQuery) || command.description.toLowerCase().includes(commandQuery))
    .slice(0, 8));
  const selectedModel = $derived(pick || currentModel);
  const modelOptions = $derived.by(() => {
    const options = models.map((model) => ({
      value: model.id,
      label: model.id === pick ? `${model.name} · picked` : model.name,
      hint: model.description,
    }));
    if (pick && !models.some((model) => model.id === pick)) {
      options.unshift({
        value: pick,
        label: `${pick} · picked`,
        hint: pickUnavailable ? "Not available in this session" : "Picked for this harness",
      });
    }
    return options;
  });
  const usagePercent = $derived(usage && usage.size > 0 ? Math.min(100, (usage.used / usage.size) * 100) : 0);


  function resizeField() {
    if (!focusTarget) return;
    focusTarget.style.height = "auto";
    const lineHeight = Number.parseFloat(getComputedStyle(focusTarget).lineHeight) || 22;
    focusTarget.style.height = `${Math.min(focusTarget.scrollHeight, lineHeight * 8)}px`;
  }

  function submit() {
    if (busy) {
      oncancel();
      return;
    }
    if (!draft.trim() && images.length === 0) return;
    onsend(draft, images);
    images = [];
    void tick().then(resizeField);
  }

  function completeCommand(command: CommandInfo) {
    const name = command.name.startsWith("/") ? command.name : `/${command.name}`;
    ondraft(`${name} `);
    commandOpen = false;
    void tick().then(() => {
      focusTarget?.focus();
      resizeField();
    });
  }

  function handleKey(event: KeyboardEvent) {
    if (event.key === "Escape" && busy) {
      event.preventDefault();
      event.stopPropagation();
      oncancel();
      return;
    }
    if (commandOpen && commandMatches.length) {
      if (event.key === "ArrowDown") {
        event.preventDefault();
        commandIndex = (commandIndex + 1) % commandMatches.length;
        return;
      }
      if (event.key === "ArrowUp") {
        event.preventDefault();
        commandIndex = (commandIndex - 1 + commandMatches.length) % commandMatches.length;
        return;
      }
      if (event.key === "Enter") {
        event.preventDefault();
        completeCommand(commandMatches[commandIndex]!);
        return;
      }
      if (event.key === "Escape") {
        event.preventDefault();
        commandOpen = false;
        return;
      }
    }
    if (event.key === "Enter" && !event.shiftKey && !event.isComposing) {
      event.preventDefault();
      submit();
    }
  }

  function readImages(files: File[]) {
    for (const file of files) {
      if (!file.type.startsWith("image/")) continue;
      const reader = new FileReader();
      reader.addEventListener("load", () => {
        const encoded = String(reader.result ?? "");
        const comma = encoded.indexOf(",");
        if (comma < 0) return;
        images = [...images, { data: encoded.slice(comma + 1), mimeType: file.type }];
      });
      reader.readAsDataURL(file);
    }
  }

  function handlePaste(event: ClipboardEvent) {
    const files = Array.from(event.clipboardData?.files ?? []).filter((file) => file.type.startsWith("image/"));
    if (files.length === 0) return;
    event.preventDefault();
    readImages(files);
  }

  $effect(() => {
    commandOpen = commandQuery !== null && commandMatches.length > 0;
    commandIndex = Math.min(commandIndex, Math.max(0, commandMatches.length - 1));
  });

  $effect(() => {
    if (commandOpen && (commandQuery === null || commandMatches.length === 0)) commandOpen = false;
  });

  $effect(() => {
    void draft;
    void tick().then(resizeField);
  });
</script>

<div class="composer-shell">
  {#key waiting}
    <BorderBeam size={waiting ? "pulse-inner" : "line"} active={busy || waiting} strength={waiting ? 0.7 : 0.9} />
  {/key}
  <div class="composer-inner">

    {#if images.length}
      <div class="attachments" aria-label="Attached images">
        {#each images as image, index (`${image.data.slice(0, 20)}:${index}`)}
          <figure>
            <img src={`data:${image.mimeType};base64,${image.data}`} alt="Prompt attachment" />
            <IconButton icon="close" label="Remove image" size={22} tip={false} onclick={() => images = images.filter((_, at) => at !== index)} />
          </figure>
        {/each}
      </div>
    {/if}

    <div class="field-anchor">
      <div class="field">
        <IconButton icon="image" label="Attach an image" size={30} onclick={() => filePicker?.click()} />
        <textarea
          bind:this={focusTarget}
          value={draft}
          rows="1"
          placeholder={handoffPending ? "Continue from the ask…" : lane === "ryoku" ? "Ask the Needle…" : `Message ${agent || "Hermes"}…`}
          aria-label={lane === "ryoku" ? "Message the Needle" : `Message ${agent || "Hermes"}`}
          oninput={(event) => {
            ondraft(event.currentTarget.value);
            resizeField();
          }}
          onkeydown={handleKey}
          onpaste={handlePaste}
        ></textarea>
        <div class="send-swap">
          {#key busy}
            <Tooltip text={busy ? "Stop response" : "Send message"} side="top">
              <Button
                variant="plate"
                class="send-action"
                icon={busy ? "stop" : "arrowUp"}
                aria-label={busy ? "Stop response" : "Send message"}
                armed={busy || Boolean(draft.trim()) || images.length > 0}
                onclick={submit}
              />
            </Tooltip>
          {/key}
        </div>
      </div>
      {#if commandOpen}
      <div class="command-menu" role="listbox" aria-label="Slash commands">
        {#each commandMatches as command, index (command.name)}
          <button
            type="button"
            role="option"
            aria-selected={index === commandIndex}
            class:active={index === commandIndex}
            onpointerenter={() => commandIndex = index}
            onclick={() => completeCommand(command)}
          >
            <span class="command-name">/{command.name.replace(/^\//, "")}</span>
            <span class="command-description">{command.description}</span>
            {#if command.hint}<span class="command-hint">{command.hint}</span>{/if}
          </button>
        {/each}
      </div>
      {/if}
    </div>

    <input
      class="file-picker"
      bind:this={filePicker}
      type="file"
      accept="image/*"
      multiple
      onchange={(event) => {
        readImages(Array.from(event.currentTarget.files ?? []));
        event.currentTarget.value = "";
      }}
    />

    <div class="status-line">
      <div class="activity" aria-live="polite">
        {#if busy}
          <ThinkingOrb mode={waiting ? "listening" : "working"} size={20} label={waiting ? "Waiting for you" : "Working"} />
          <span class="activity-text" title={activity}>{waiting ? "waiting for your approval" : (activity || "working")}</span>
        {:else if !connected}
          <span class="activity-text">reconnecting</span>
        {/if}
      </div>
      <div class="composer-controls">
        {#if usage}
          <div class="usage" title={`${tokenLabel(usage.used)} of ${tokenLabel(usage.size)} tokens used`}>
            <span>{tokenLabel(usage.used)}/{tokenLabel(usage.size)}</span>
            <span class="usage-bar"><i style:width={`${usagePercent}%`}></i></span>
          </div>
        {/if}
        <span class="agent-hint">{agent || "agent"}</span>
        <div class="model-control">
          <Select
            size="sm"
            label="Model"
            options={modelOptions}
            value={selectedModel}
            placeholder="Model"
            onchange={onmodel}
          />
          {#if pickUnavailable}
            <span class="pick-note" role="status">Your pick, {pick}, is not available in this session. The agent kept {currentModel || "its current model"}.</span>
          {/if}
        </div>
        <Tooltip text={APPROVAL_HINTS[approvals]} side="top">
          <Seg
            size="sm"
            label="What runs without asking"
            options={APPROVAL_OPTIONS}
            value={approvals}
            onchange={(value) => onapprovals(value as ApprovalsMode)}
          />
        </Tooltip>
      </div>
    </div>
  </div>
</div>

<style>
  .composer-shell { position: relative; z-index: 3; flex: none; border-top: 1px solid var(--line-soft); background: var(--paper); }
  .composer-inner { width: min(100%, var(--measure)); margin: 0 auto; padding: var(--s3) var(--s5) var(--s4); }

  .field { display: flex; align-items: flex-end; gap: var(--s2); padding: var(--s2); border: 1px solid var(--line); border-radius: var(--radius); background: var(--paper-lift); transition: border-color var(--t-fast) var(--ease); }
  .field:focus-within { border-color: var(--line-strong); }
  textarea { flex: 1; min-width: 0; min-height: 32px; max-height: 176px; resize: none; overflow-y: auto; padding: 5px var(--s1); border: 0; outline: 0; background: transparent; color: var(--ink); line-height: 22px; }
  textarea::placeholder { color: var(--ink-faint); }
  .send-swap { flex: none; }
  :global(.send-action) { width: 34px; padding: 0; animation: action-in var(--t-fast) var(--ease-out); }
  @keyframes action-in { from { opacity: 0; transform: scale(0.82) rotate(-8deg); } }
  .file-picker { position: absolute; width: 1px; height: 1px; overflow: hidden; clip-path: inset(50%); }
  .attachments { display: flex; gap: var(--s2); margin-bottom: var(--s2); overflow-x: auto; }
  figure { position: relative; flex: none; width: 88px; height: 64px; }
  figure img { width: 100%; height: 100%; border: 1px solid var(--line); border-radius: var(--radius); object-fit: cover; }
  figure :global(.ib) { position: absolute; top: var(--s1); right: var(--s1); border-color: var(--line-strong); background: var(--paper-lift); }
  .status-line { display: flex; align-items: center; justify-content: space-between; gap: var(--s3); min-height: 30px; padding-top: var(--s2); }
  .activity { display: flex; align-items: center; gap: var(--s2); flex: 1 1 0; min-width: 0; color: var(--ink-mute); font-size: var(--f-small); }
  .activity-text { min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .composer-controls { display: flex; align-items: center; justify-content: flex-end; gap: var(--s2); flex: none; }
  .agent-hint { color: var(--ink-faint); font-size: var(--f-micro); }
  .model-control { display: flex; align-items: center; gap: var(--s2); max-width: 360px; }
  .pick-note { color: var(--alert); font-size: var(--f-micro); line-height: 1.3; }
  .usage { display: grid; grid-template-columns: auto 56px; align-items: center; gap: var(--s2); color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); }
  .usage-bar { position: relative; width: 56px; height: 3px; overflow: hidden; border-radius: 2px; background: var(--tint10); }
  .usage-bar i { position: absolute; inset: 0 auto 0 0; border-radius: inherit; background: var(--bone); transition: width var(--t-slow) var(--ease-out); }
  .field-anchor { position: relative; }
  /* The slash menu is a typeahead anchored over the field, not a popover: a
     popover trigger owns Space and Enter as a button would, which is how a
     space typed into the message went missing. */
  .command-menu { position: absolute; left: 0; right: 0; bottom: calc(100% + var(--s2)); z-index: 20; display: flex; flex-direction: column; max-height: 320px; overflow: auto; padding: var(--s2); border: 1px solid var(--line-strong); border-radius: var(--radius); background: var(--paper-lift); animation: menu-rise var(--t-fast) var(--ease-out); }
  @keyframes menu-rise { from { opacity: 0; transform: translateY(4px); } }
  .command-menu button { display: grid; grid-template-columns: 112px minmax(0, 1fr) auto; align-items: center; gap: var(--s3); min-height: 38px; padding: var(--s2) var(--s3); border-radius: 4px; text-align: left; }
  .command-menu button.active { background: var(--tint10); }
  .command-name { color: var(--ink); font-family: var(--mono); font-size: var(--f-small); }
  .command-description { overflow: hidden; color: var(--ink-mute); font-size: var(--f-small); text-overflow: ellipsis; white-space: nowrap; }
  .command-hint { color: var(--ink-faint); font-family: var(--mono); font-size: var(--f-tiny); }
  @media (max-width: 760px) {
    .composer-inner { padding: var(--s3) var(--s4); }
    .status-line { align-items: flex-start; flex-direction: column; }
    .composer-controls { width: 100%; justify-content: flex-start; flex-wrap: wrap; }
    .agent-hint { display: none; }
  }
</style>
