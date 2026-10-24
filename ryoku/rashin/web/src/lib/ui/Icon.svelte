<script lang="ts">
  import { ICONS, type IconName } from "./icons";

  interface Props {
    name: IconName;
    size?: number;
    /** stroke width in viewbox units; 1.5 is the hairline weight */
    weight?: number;
  }

  let { name, size = 16, weight = 1.5 }: Props = $props();
</script>

<svg
  class="icon"
  width={size}
  height={size}
  viewBox="0 0 24 24"
  fill="none"
  stroke="currentColor"
  stroke-width={weight}
  stroke-linecap="round"
  stroke-linejoin="round"
  aria-hidden="true"
>
  <path d={ICONS[name]} />
</svg>

<style>
  .icon { flex: none; display: inline-block; vertical-align: middle; }
</style>
