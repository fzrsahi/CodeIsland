<script lang="ts">
  // Render and input only (docs/plan-windows-linux.md §5.3): the shell owns
  // the sessions and the window; this file draws what it is sent and reports
  // the island's size so the shell can fit the window to it.
  import { onMount } from 'svelte';
  import { Channel, invoke } from '@tauri-apps/api/core';

  // `Snapshot` in src-tauri/src/sessions.rs. Sessions arrive newest first.
  type Session = {
    session_id: string;
    source: string;
    last_event: string;
    cwd_name: string;
    updated_at: number;
  };
  type Snapshot = { sessions: Session[] };

  let sessions = $state<Session[]>([]);
  let expanded = $state(false);
  let island: HTMLElement;

  onMount(() => {
    const channel = new Channel<Snapshot>();
    channel.onmessage = (snapshot) => {
      sessions = snapshot.sessions;
    };
    invoke('subscribe', { channel });

    // Tight-fit window: the window is as big as the island and no bigger.
    // Measured after every layout change (collapse, expand, a new row).
    const observer = new ResizeObserver(() => {
      invoke('set_island_size', { width: island.offsetWidth, height: island.offsetHeight });
    });
    observer.observe(island);
    return () => observer.disconnect();
  });
</script>

<button class="island" class:expanded bind:this={island} onclick={() => (expanded = !expanded)}>
  <div class="pill">
    <span class="dot" class:live={sessions.length > 0}></span>
    {#if sessions.length > 0}
      <span class="count">{sessions.length}</span>
      <span class="source">{sessions[0].source}</span>
    {:else}
      <span class="source">Morrow</span>
    {/if}
  </div>
  {#if expanded}
    <ul class="list">
      {#each sessions as session (session.session_id)}
        <li>
          <span class="source">{session.source}</span>
          <span class="cwd">{session.cwd_name || session.session_id}</span>
          <span class="event">{session.last_event}</span>
        </li>
      {:else}
        <li class="empty">No sessions</li>
      {/each}
    </ul>
  {/if}
</button>

<style>
  :global(html),
  :global(body) {
    margin: 0;
    padding: 0;
    background: transparent;
    overflow: hidden;
  }

  /* Fixed widths, so the measured size never depends on the window's. */
  .island {
    position: absolute;
    top: 0;
    left: 0;
    box-sizing: border-box;
    width: 240px;
    margin: 0;
    padding: 0 14px;
    border: 0;
    border-radius: 0 0 17px 17px;
    background: #000;
    color: #f2f2f2;
    font: 13px/1.2 system-ui, sans-serif;
    text-align: left;
    cursor: default;
  }
  .island.expanded {
    width: 360px;
    padding-bottom: 10px;
    border-radius: 0 0 20px 20px;
  }

  .pill {
    display: flex;
    align-items: center;
    gap: 8px;
    height: 34px;
  }
  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: #555;
  }
  .dot.live {
    background: #34c759;
  }
  .count {
    font-weight: 600;
  }
  .source {
    color: #d0d0d0;
  }

  .list {
    list-style: none;
    margin: 0;
    padding: 0;
  }
  .list li {
    display: grid;
    grid-template-columns: 70px 1fr auto;
    gap: 8px;
    padding: 6px 0;
    border-top: 1px solid #222;
  }
  .cwd {
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .event {
    color: #8e8e93;
  }
  .empty {
    color: #8e8e93;
  }
</style>
