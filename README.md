# HAmp – Amp for Home Assistant

A Home Assistant add-on repository with one add-on, **Amp Runner**, which turns your Home
Assistant machine (Home Assistant Green, Yellow, or any HAOS/Supervised install) into an
[Amp runner](https://ampcode.com/docs/cli/runners). Start a thread from ampcode.com or the Amp
iOS/macOS app, pick the `home-assistant` runner, and the agent runs on the box with full access
to Home Assistant:

- "Turn off the living room lights and the TV."
- "Suggest automations based on my energy usage and the devices I have."
- "When the Miele washer finishes its program, turn it off and notify my phone."

## Install

1. In Home Assistant: **Settings → Add-ons → Add-on Store → ⋮ → Repositories**, paste
   `https://github.com/nclandrei/HAmp`, **Add**, then close and refresh the store.
2. Install **Amp Runner** from the new "HAmp" section. The Green pulls a pre-built image;
   it does not compile one locally.
3. Create an access token at <https://ampcode.com/settings/security>, paste it into the
   add-on's **Configuration → Amp access token**, save, **Start**.
4. Keep **Start on boot** and **Watchdog** on. The runner is now online whenever the machine is.

Then open the Amp app or ampcode.com, start a new thread, and select the runner
`home-assistant`. See [amp_runner/DOCS.md](amp_runner/DOCS.md) for options and details.

## How it works

```diagram
┌──────────────────────┐   HTTPS   ┌──────────────────────────────────────────────────┐
│ Amp iOS / Web / CLI  │──────────▶│ Home Assistant OS                                │
│  new thread on       │           │ ┌──────────────────────────────────────────────┐ │
│  runner:home-assist. │◀──────────│ │ Amp Runner add-on (Debian container)         │ │
└──────────────────────┘ ampcode.com│ │  amp --no-tui --runner-id home-assistant     │ │
                                   │ │  workspace: /data/workspace (AGENTS.md, bin/)│ │
                                   │ └───────────────┬──────────────────────────────┘ │
                                   │                 │ SUPERVISOR_TOKEN               │
                                   │                 ▼                                │
                                   │ ┌───────────────────────┐  ┌───────────────────┐ │
                                   │ │ Supervisor            │─▶│ Home Assistant    │ │
                                   │ │ /core/api, /core/ws   │  │ Core (REST + WS)  │ │
                                   │ └───────────────────────┘  └───────────────────┘ │
                                   └──────────────────────────────────────────────────┘
```

The add-on declares `homeassistant_api` and `hassio_api` (role `admin`), so threads talk to
Home Assistant through the Supervisor proxy with the token the Supervisor injects. No
long-lived Home Assistant token is created or stored. The Amp CLI itself keeps up to date on
its own; the add-on only needs updating when its own files change.

## Layout

```
repository.yaml                  add-on repository metadata
amp_runner/
  config.yaml                    add-on manifest (permissions, options, schema)
  Dockerfile                     Debian base + Amp CLI + curl/jq/python3-websockets/git
  rootfs/run.sh                  starts the runner, keeps it alive
  rootfs/opt/workspace/          template for the served workspace
    AGENTS.md                    how the agent operates Home Assistant
    bin/ha, bin/ha-ws            REST and WebSocket helpers
  DOCS.md, CHANGELOG.md, translations/en.yaml
.github/workflows/build.yaml    builds aarch64 and amd64, publishes the multi-arch image
```
