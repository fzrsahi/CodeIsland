<script lang="ts">
  // Render and input only (docs/plan-windows-linux.md §5.3): the shell owns
  // the sessions, the permission requests and the window; this file draws
  // what it is sent, reports the island's size so the shell can fit the
  // window to it, and passes on the user's Approve / Deny.
  import { onMount } from 'svelte';
  import { Channel, invoke } from '@tauri-apps/api/core';

  // `Snapshot` in src-tauri/src/feed.rs. Sessions arrive newest first,
  // cards oldest first.
  type Session = {
    session_id: string;
    source: string;
    last_event: string;
    cwd_name: string;
    updated_at: number;
  };
  type Card = { id: number; session_id: string; source: string; tool_name: string; summary: string };
  type Snapshot = { sessions: Session[]; permissions: Card[] };
  type Decision = 'allow' | 'deny';

  let sessions = $state<Session[]>([]);
  let cards = $state<Card[]>([]);
  let expanded = $state(false);
  let island: HTMLElement;

  function answer(id: number, decision: Decision) {
    invoke('answer_permission', { id, decision });
  }

  // For the E2E-1 gate (the shell prints them only with MORROW_SMOKE=1).
  function reportCards() {
    const rect = (el: Element | null) => {
      const r = el!.getBoundingClientRect();
      return { x: r.x, y: r.y, width: r.width, height: r.height };
    };
    for (const el of island.querySelectorAll<HTMLElement>('[data-card]')) {
      invoke('smoke_card', {
        id: Number(el.dataset.card),
        approve: rect(el.querySelector('.approve')),
        deny: rect(el.querySelector('.deny')),
      });
    }
  }

  onMount(() => {
    const channel = new Channel<Snapshot>();
    channel.onmessage = (snapshot) => {
      sessions = snapshot.sessions;
      cards = snapshot.permissions;
    };
    invoke('subscribe', { channel });

    // Tight-fit window: the window is as big as the island and no bigger.
    // Measured after every layout change (collapse, expand, a row, a card).
    const observer = new ResizeObserver(() => {
      invoke('set_island_size', { width: island.offsetWidth, height: island.offsetHeight }).then(
        reportCards,
      );
    });
    observer.observe(island);
    return () => observer.disconnect();
  });
</script>

<div class="island" class:wide={expanded || cards.length > 0} bind:this={island}>
  <button class="toggle" onclick={() => (expanded = !expanded)}>
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
  {#each cards as card (card.id)}
    <section class="card" data-card={card.id}>
      <div class="tool"><span class="source">{card.source}</span> {card.tool_name}</div>
      {#if card.summary}<div class="summary">{card.summary}</div>{/if}
      <div class="actions">
        <button class="deny" onclick={() => answer(card.id, 'deny')}>Deny</button>
        <button class="approve" onclick={() => answer(card.id, 'allow')}>Approve</button>
      </div>
    </section>
  {/each}
</div>

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
  .island.wide {
    width: 360px;
    padding-bottom: 10px;
    border-radius: 0 0 20px 20px;
  }
  .toggle {
    display: block;
    width: 100%;
    margin: 0;
    padding: 0;
    border: 0;
    background: none;
    color: inherit;
    font: inherit;
    text-align: inherit;
    cursor: default;
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

  .card {
    padding: 8px 0 0;
    border-top: 1px solid #222;
  }
  .tool {
    font-weight: 600;
  }
  .summary {
    margin-top: 4px;
    color: #c7c7cc;
    font-family: ui-monospace, monospace;
    font-size: 12px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }
  .actions {
    display: flex;
    justify-content: flex-end;
    gap: 8px;
    margin-top: 8px;
  }
  .actions button {
    width: 84px;
    height: 28px;
    border: 0;
    border-radius: 14px;
    font: inherit;
    font-weight: 600;
    cursor: default;
  }
  .deny {
    background: #3a3a3c;
    color: #f2f2f2;
  }
  .approve {
    background: #f2f2f2;
    color: #000;
  }
</style>
