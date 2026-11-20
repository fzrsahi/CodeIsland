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

  // `Status` in ../../crates/morrow-platform/src/hooks.rs, by way of
  // src-tauri/src/hooks.rs. The card only reports and asks.
  type HooksStatus = {
    codeisland_dir: string;
    script_installed: boolean;
    bridge_installed: boolean;
    hooks_installed: boolean;
    settings: string;
    settings_exists: boolean;
  };
  type TargetStatus = {
    source: string;
    name: string;
    detected: boolean;
    installed: boolean;
    path: string;
  };
  type OpencodeStatus = {
    detected: boolean;
    plugin_installed: boolean;
    registered: boolean;
    config: string;
  };
  type HooksSnapshot = {
    status: HooksStatus;
    targets: TargetStatus[];
    opencode: OpencodeStatus;
    version: string | null;
  };

  let sessions = $state<Session[]>([]);
  let cards = $state<Card[]>([]);
  let expanded = $state(false);
  let hooks = $state<HooksSnapshot | null>(null);
  let hooksBusy = $state(false);
  let hooksError = $state<string | null>(null);
  let island: HTMLElement;

  function answer(id: number, decision: Decision) {
    invoke('answer_permission', { id, decision });
  }

  async function loadHooks() {
    try {
      hooks = await invoke<HooksSnapshot>('hooks_status');
      hooksError = null;
    } catch (error) {
      hooksError = String(error);
    }
  }

  async function runHooks(command: 'hooks_install' | 'hooks_uninstall') {
    await run(() => invoke(command));
  }

  // One of the other CLIs: install when its file has no hook of ours, remove
  // when it has. The shell skips a CLI that is not on this machine.
  async function toggleTarget(row: TargetStatus) {
    await run(() =>
      invoke(row.installed ? 'target_uninstall' : 'target_install', { source: row.source }),
    );
  }

  // OpenCode is a plugin file, not a hooks key, so it gets its own row.
  async function toggleOpencode(row: OpencodeStatus) {
    await run(() =>
      invoke(row.plugin_installed ? 'opencode_uninstall' : 'opencode_install'),
    );
  }

  async function run(action: () => Promise<unknown>) {
    hooksBusy = true;
    try {
      await action();
      await loadHooks();
    } catch (error) {
      hooksError = String(error);
    } finally {
      hooksBusy = false;
    }
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
    loadHooks();

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
  {#if expanded}
    <div class="hooks">
      <div class="hooks-title">
        Claude Code hooks{#if hooks?.version}&nbsp;· {hooks.version}{/if}
      </div>
      {#if hooks}
        <div class="hooks-line">
          {hooks.status.hooks_installed ? 'Installed' : 'Not installed'}
          {#if hooks.status.script_installed}&nbsp;· script{/if}
          {#if hooks.status.bridge_installed}&nbsp;· bridge{/if}
        </div>
        <div class="hooks-actions">
          <button class="hooks-button" disabled={hooksBusy} onclick={() => runHooks('hooks_install')}>
            {hooks.status.hooks_installed ? 'Repair' : 'Install'}
          </button>
          {#if hooks.status.hooks_installed || hooks.status.script_installed}
            <button class="hooks-button" disabled={hooksBusy} onclick={() => runHooks('hooks_uninstall')}>
              Remove
            </button>
          {/if}
        </div>
        {#if hooks.targets.length > 0}
          <ul class="hooks-targets">
            {#each hooks.targets as row (row.source)}
              <li class:missing={!row.detected}>
                <span class="hooks-name">{row.name}</span>
                <span class="hooks-state">
                  {row.installed ? 'Installed' : row.detected ? 'Not installed' : 'Not detected'}
                </span>
                {#if row.detected}
                  <button class="hooks-button" disabled={hooksBusy} onclick={() => toggleTarget(row)}>
                    {row.installed ? 'Remove' : 'Install'}
                  </button>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
        {#if hooks.opencode}
          <div class="hooks-targets">
            <ul>
              <li class:missing={!hooks.opencode.detected}>
                <span class="hooks-name">OpenCode</span>
                <span class="hooks-state">
                  {hooks.opencode.plugin_installed && hooks.opencode.registered
                    ? 'Installed'
                    : hooks.opencode.detected
                      ? 'Not installed'
                      : 'Not detected'}
                </span>
                {#if hooks.opencode.detected}
                  <button
                    class="hooks-button"
                    disabled={hooksBusy}
                    onclick={() => toggleOpencode(hooks!.opencode)}
                  >
                    {hooks.opencode.plugin_installed ? 'Remove' : 'Install'}
                  </button>
                {/if}
              </li>
            </ul>
          </div>
        {/if}
      {:else}
        <div class="hooks-line">Checking…</div>
      {/if}
      {#if hooksError}<div class="hooks-error">{hooksError}</div>{/if}
    </div>
  {/if}
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

  .hooks {
    margin: 6px 0 2px;
    padding-top: 6px;
    border-top: 1px solid #262626;
  }
  .hooks-title {
    color: #9a9a9a;
    font-size: 11px;
    letter-spacing: 0.04em;
    text-transform: uppercase;
  }
  .hooks-line {
    margin: 4px 0 6px;
    font-size: 12px;
    color: #d0d0d0;
  }
  .hooks-actions {
    display: flex;
    gap: 6px;
  }
  .hooks-button {
    padding: 3px 10px;
    border: 1px solid #3a3a3a;
    border-radius: 6px;
    background: #1c1c1c;
    color: #f2f2f2;
    font: inherit;
    font-size: 12px;
    cursor: default;
  }
  .hooks-button:disabled {
    opacity: 0.5;
  }
  .hooks-targets {
    margin: 0 0 6px;
    padding: 0;
    list-style: none;
  }
  .hooks-targets li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 2px 0;
    font-size: 12px;
  }
  .hooks-targets li.missing {
    color: #6a6a6a;
  }
  .hooks-name {
    flex: 0 0 84px;
    overflow: hidden;
    white-space: nowrap;
    text-overflow: ellipsis;
  }
  .hooks-state {
    flex: 1;
    color: #9a9a9a;
  }
  .hooks-error {
    margin-top: 6px;
    font-size: 11px;
    color: #ff6b6b;
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
