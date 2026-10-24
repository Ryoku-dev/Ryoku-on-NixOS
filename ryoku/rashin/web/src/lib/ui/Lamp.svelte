<!-- A status dot: data, so it may carry colour. Bone is alive, hollow is
     idle, the sun is an alert. It breathes while something is in flight. -->
<script lang="ts">
  interface Props {
    state: "ok" | "idle" | "bad" | "busy";
    label?: string;
  }

  let { state, label }: Props = $props();
</script>

<span class="lamp {state}" role="status" aria-label={label} title={label}></span>

<style>
  .lamp {
    display: inline-block;
    width: 8px;
    height: 8px;
    border-radius: 50%;
    border: 1px solid var(--ink-faint);
    background: transparent;
    flex: none;
    transition: background-color var(--t-mid) var(--ease), border-color var(--t-mid) var(--ease);
  }
  .ok { background: var(--bone); border-color: var(--bone); }
  .bad { background: var(--alert); border-color: var(--alert); }
  .busy { background: var(--bone); border-color: var(--bone); animation: lamp-breathe 1.6s var(--ease) infinite; }
  @keyframes lamp-breathe { 0%, 100% { opacity: 1; } 50% { opacity: 0.35; } }
</style>
