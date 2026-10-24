<script lang="ts">
  import { chat } from "$lib/chat/store.svelte";
  import ChatWorkspace from "$lib/pages/chat/ChatWorkspace.svelte";
</script>

<ChatWorkspace store={chat} lane="chat" />
