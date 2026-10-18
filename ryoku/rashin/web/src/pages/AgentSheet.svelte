<script lang="ts">
  import { ryoku } from "$lib/chat/store.svelte";
  import ChatWorkspace from "$lib/pages/chat/ChatWorkspace.svelte";
</script>

<ChatWorkspace store={ryoku} lane="ryoku" />
