# CodeIsland

A macOS overlay that watches AI coding agents and shows what they are doing in the notch. Being ported to Windows and Linux.

## Language

### Who emits events

**Source**:
The string a hook event carries that identifies which CLI emitted it, such as `claude`, `cursor-cli`, or `traecli`. There are 34 known sources, and the reducer is keyed on this string.
_Avoid_: agent, tool, provider, integration

**Agent**:
The product identity a user recognises, shown with its own mascot and name. One agent owns one or more sources: `trae`, `traecn`, and `traecli` are all the Trae agent.
_Avoid_: source, tool, vendor

**Hook target**:
A CLI whose config file CodeIsland can write a hook into, and therefore the only kind of source that can produce events at all. Nine today, against 34 known sources.
_Avoid_: tool, integration, plugin

### What flows

**Hook event**:
The raw JSON a CLI writes to the bridge's stdin when a hook fires.
_Avoid_: message, payload, notification

**Envelope**:
The versioned wrapper the bridge puts around a hook event before sending it over IPC. The only shape both cores must agree on.
_Avoid_: packet, frame, message

**Session**:
One running conversation in one source, keyed by the session id the CLI supplies.
_Avoid_: task, run, conversation

**Effect**:
A lifecycle instruction the reducer returns for the caller to execute, such as `stopMonitor` or `setActiveSession`. The reducer never performs an effect itself.
_Avoid_: action, command, side effect

**Attention**:
Whether an event should interrupt the user, as a sound, a push, or a card. Decided by policy from the facts of an event, never by the reducer.
_Avoid_: notification, alert, interrupt

### How it is built

**Core**:
The pure domain library: reducer, attention policy, git reading, Markdown blocks, protocol encoding. Runs no process, opens no socket, imports no OS API.
_Avoid_: engine, backend, service, domain layer

**Bridge**:
The small binary a CLI invokes per hook. Reads stdin, builds an envelope, sends it, exits. Never blocks the CLI.
_Avoid_: agent, daemon, helper

**Shell**:
The OS-facing layer that owns windows, tray, hotkeys, and rendering. One per platform family.
_Avoid_: UI, frontend, app

**Frontend**:
The web layer inside a shell. Renders and takes input; holds no domain rules.
_Avoid_: UI, view layer, client

**Adapter**:
A concrete implementation of a platform interface: reading Now Playing, activating a terminal, registering a hotkey. Every adapter reports whether it is supported before it is used.
_Avoid_: provider, driver, integration

### What the user sees

**Island**:
The product surface: a collapsed pill that expands into a panel.
_Avoid_: notch, widget, overlay

**Panel**:
The floating window that hosts the island. Always on top, out of the taskbar, never takes focus from the app behind it.
_Avoid_: window, overlay, HUD

**Notch**:
The physical cutout on a MacBook display. A hardware fact, not a UI concept.
_Avoid_: island, panel

### What is shared

**Contract**:
The frozen hook-event schema, envelope schema, and golden fixtures that both cores must satisfy. The only thing that may not drift.
_Avoid_: spec, protocol (the protocol is one part of the contract)
