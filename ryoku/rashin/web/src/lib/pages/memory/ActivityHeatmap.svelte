<script lang="ts">
  import { bucketHeatmap, type HeatmapEntry } from "./graph";

  interface Props {
    entries: HeatmapEntry[];
  }

  let { entries }: Props = $props();
  const months = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"];
  const heatmap = $derived(bucketHeatmap(entries, 26));
  const monthLabels = $derived.by(() => {
    let previous = -1;
    return Array.from({ length: heatmap.weeks }, (_, column) => {
      const month = new Date(`${heatmap.days[column * 7]!.date}T00:00:00Z`).getUTCMonth();
      if (month === previous) return "";
      previous = month;
      return months[month];
    });
  });

  function level(count: number): number {
    if (count <= 0) return 0;
    if (count === 1) return 1;
    if (count <= 3) return 2;
    return 3;
  }
</script>

<div class="heatmap" aria-label="Memory activity over 26 weeks">
  <div class="months" aria-hidden="true">
    {#each monthLabels as label}<span>{label}</span>{/each}
  </div>
  <div class="cells">
    {#each heatmap.days as day (day.date)}
      <span
        class="cell"
        class:future={day.future}
        data-level={day.future ? 0 : level(day.count)}
        title={day.future ? "" : `${day.date}: ${day.count}`}
      ></span>
    {/each}
  </div>
</div>

<style>
  .heatmap { width: fit-content; max-width: 100%; overflow-x: auto; padding-bottom: var(--s1); }
  .months { display: grid; grid-template-columns: repeat(26, 10px); margin-bottom: var(--s1); font-family: var(--mono); font-size: var(--f-tiny); color: var(--ink-faint); }
  .cells { display: grid; grid-auto-flow: column; grid-template-rows: repeat(7, 10px); }
  .cell { width: 8px; height: 8px; margin: 1px; border-radius: 2px; background: var(--tint10); }
  .cell[data-level="1"] { background: color-mix(in srgb, var(--sun) 30%, transparent); }
  .cell[data-level="2"] { background: color-mix(in srgb, var(--sun) 58%, transparent); }
  .cell[data-level="3"] { background: var(--sun); }
  .cell.future { opacity: 0.25; }
</style>
