# Amp Runner

Runs an [Amp runner](https://ampcode.com/docs/cli/runners) inside Home Assistant. Once it is
running, this machine appears in the runner picker on ampcode.com and in the Amp iOS/macOS
apps, and any thread you start there runs here with full access to Home Assistant.

## Setup

1. Create an access token at <https://ampcode.com/settings/security> (it starts with `sgamp_`).
2. Open the add-on's **Configuration** tab, paste the token into **Amp access token**, save.
3. **Start** the add-on. Turn on **Start on boot** and **Watchdog** if they aren't already on.
4. Open ampcode.com or the Amp app, start a new thread, and pick the runner named
   `home-assistant` (or whatever you set as **Runner name**). Two directories are offered:
   the runner's workspace (default, recommended) and `/homeassistant` (the Home Assistant
   config directory).

The first start downloads the pre-built image; it does not build on the device.

## What threads can do

Threads run inside the add-on container as the add-on's Supervisor identity. They can:

- read every entity, device, area and service (`http://supervisor/core/api`, WebSocket)
- call any service (lights, media players, climate, covers, locks, ...)
- read history and long-term statistics, including the Energy dashboard's data
- create, edit and delete automations, scripts, scenes and helpers
- read and write the Home Assistant config directory (`/homeassistant`), `/share`, `/backup`
- use the Supervisor API (restart Core, manage add-ons, create backups)

The workspace ships an `AGENTS.md` and two helper commands, `ha` (REST) and `ha-ws`
(WebSocket), so the agent knows how to do all of this without being told. Edit
`AGENTS.md` in the workspace to add house rules or notes about your home; the add-on keeps
your edits (and stops shipping its own updates to that file). `bin/` is restored on every
start.

There are no guardrails. Whoever can start a thread on this runner controls your home. Keep
**Share with workspace** off unless you trust every member of your Amp workspace.

## Options

| Option | Default | Description |
| --- | --- | --- |
| `amp_api_key` | – | Access token from ampcode.com (`sgamp_...`). Required. |
| `runner_id` | `home-assistant` | Name shown in the runner picker. Must be a valid hostname. |
| `remote_terminal` | `true` | Enables the Terminal pane in threads on ampcode.com. |
| `amp_env` | `false` | Inject Secrets & Env Vars configured on ampcode.com into threads. |
| `share_runner` | `false` | Share the runner with your whole Amp workspace. |
| `log_level` | `info` | Add-on log verbosity. |

## Updates

The Amp CLI updates itself: the runner checks hourly and restarts into the new version when no
thread is running. Updating the add-on itself only matters for changes to the add-on's own
files (`AGENTS.md`, helper scripts, configuration).

## Where things are stored

Everything persists in the add-on's `/data` volume, which is included in Home Assistant
backups:

- `/data/home` – Amp's home (`~/.config/amp`, `~/.amp`, logs)
- `/data/workspace` – the runner's workspace, a Git repository
