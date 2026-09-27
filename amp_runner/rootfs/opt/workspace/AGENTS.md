# You are running inside Home Assistant

This workspace lives in the **Amp Runner add-on** on the user's Home Assistant machine
(Home Assistant OS). Threads here exist to operate the home: inspect devices, control them,
analyse history and energy data, and create or change automations. Treat every prompt as an
instruction to act, not as a request for a plan.

## Ground rules

- Act directly. The user deliberately runs this runner without guardrails: turn things on and
  off, create/edit/delete automations, restart Home Assistant if needed. Do not ask for
  confirmation before acting; report what you did afterwards.
- Verify by reading state back after a service call (`ha GET states/<entity_id>`), and check
  the response of every config write. Say clearly when something failed or when the device
  has no entity/service for what was asked (e.g. an appliance whose door cannot be opened via
  its integration).
- Prefer the API over editing YAML by hand. Automations, scripts and scenes created through
  the config API are stored by Home Assistant itself and reload automatically.
- Discover before you act: entity IDs, friendly names, areas and supported services differ per
  home. Never guess an entity ID; look it up.
- The user is usually on a phone. Keep answers short: what changed, entity IDs touched, and
  anything that needs their attention.

## Environment

- `SUPERVISOR_TOKEN` (env var) authenticates against the Supervisor proxy. No other token is
  needed.
- Home Assistant REST API: `http://supervisor/core/api/...` (GET, POST, DELETE).
- Home Assistant WebSocket API: `ws://supervisor/core/websocket`.
- Supervisor API (add-ons, backups, core/host control): `http://supervisor/...`.
- `/homeassistant` is the Home Assistant config directory, mounted read-write
  (`configuration.yaml`, `automations.yaml`, `scripts.yaml`, `.storage/`, ...).
- `/share` is the shared folder; `/backup` holds backups.
- `bin/ha` and `bin/ha-ws` (on `PATH`) wrap the two APIs. `curl`, `jq`, `python3`, `git` are
  installed. There is no `docker` and no access to the host OS.

## Helper commands

```bash
ha GET states                                   # every entity with state + attributes
ha GET states/light.kitchen
ha GET services                                 # every domain with its services and fields
ha POST services/light/turn_on  '{"entity_id":"light.kitchen","brightness_pct":40}'
ha POST services/media_player/turn_off '{"entity_id":"media_player.living_room_tv"}'
ha POST config/automation/config/<id> @automation.json
ha GET  config/automation/config/<id>
ha DELETE config/automation/config/<id>
ha sup GET core/info                            # Supervisor API
ha-ws '{"type":"config/entity_registry/list"}'  # WebSocket command, prints the result
ha-ws --events 3 '{"type":"subscribe_events","event_type":"state_changed"}'
```

`ha` prints the raw response body; pipe into `jq` for filtering. Both exit non-zero on errors.

## Recipes

### Find entities and devices

```bash
# entity_id, state, friendly name — grep this to find what the user means
ha GET states | jq -r '.[] | [.entity_id, .state, (.attributes.friendly_name // "")] | @tsv'
ha GET states | jq -r '.[] | select(.attributes.friendly_name // "" | test("tv|washer"; "i")) | .entity_id'

# registries: which device/area an entity belongs to, integration (platform), device model
ha-ws '{"type":"config/entity_registry/list"}' | jq '.result[] | {entity_id, name, original_name, device_id, area_id, platform}'
ha-ws '{"type":"config/device_registry/list"}' | jq '.result[] | {id, name, manufacturer, model, area_id}'
ha-ws '{"type":"config/area_registry/list"}'  | jq '.result[] | {area_id, name}'
```

When the user names something loosely ("the TV", "those lights"), match on friendly name and
area; if several candidates remain, pick the obvious one and say which you picked.

### Control devices

Look up the service and its fields first if unsure: `ha GET services | jq '.[] | select(.domain=="media_player") | .services | keys'`.

Common ones: `light.turn_on/turn_off/toggle`, `switch.turn_on/turn_off`,
`media_player.turn_off/media_pause/volume_set`, `climate.set_temperature`,
`cover.open_cover/close_cover`, `lock.lock/unlock`, `button.press`, `scene.turn_on`,
`script.turn_on`, `automation.trigger`, `homeassistant.turn_off` (works for any domain).
`entity_id` may be a list, or `"all"` for a domain. Target by area with `{"area_id":"kitchen"}`.

### History, statistics and energy

```bash
# raw state history for one or more entities (times are ISO 8601)
ha GET "history/period/2026-09-26T00:00:00+00:00?filter_entity_id=sensor.washer_power&end_time=2026-09-27T00:00:00+00:00&minimal_response" | jq '.[0] | length'

# long-term statistics (hour/day/week/month) for energy or power sensors
ha-ws '{"type":"recorder/list_statistic_ids","statistic_type":"sum"}' | jq '.result[] | {statistic_id, name, unit_of_measurement}'
ha-ws '{"type":"recorder/statistics_during_period","start_time":"2026-09-01T00:00:00+00:00","period":"day","statistic_ids":["sensor.grid_energy_import"],"types":["change"]}'

# what the Energy dashboard is configured with (grid, solar, individual devices)
ha-ws '{"type":"energy/get_prefs"}'
ha-ws '{"type":"energy/info"}'
```

For "suggest automations from my energy usage/devices": pull `energy/get_prefs` to see the
tracked devices, get daily `change` statistics for them, look at the device and entity
registries for controllable entities in the same areas, then propose concrete automations
with the exact entity IDs. Offer to create them, or create them straight away if the user
asked for that.

### Automations, scripts, scenes

Write the automation as JSON and POST it. The `<id>` in the URL becomes the automation's
unique id; use a short slug. Home Assistant writes it to `automations.yaml` and loads it
immediately; the entity becomes `automation.<alias_slug>`.

```bash
cat > /tmp/washer_done.json <<'EOF'
{
  "alias": "Washer finished: power off",
  "description": "Created by Amp",
  "mode": "single",
  "triggers": [
    { "trigger": "state", "entity_id": "sensor.washing_machine_status", "from": "running", "to": "finished" }
  ],
  "conditions": [],
  "actions": [
    { "action": "switch.turn_off", "target": { "entity_id": "switch.washing_machine_power" } }
  ]
}
EOF
ha POST config/automation/config/washer_done @/tmp/washer_done.json
ha GET states/automation.washer_finished_power_off
```

Trigger types you will use most: `state` (with `from`/`to`/`for`), `numeric_state`
(`above`/`below`), `time`, `sun`, `template`, `event`. Add `"for": {"minutes": 5}` to avoid
flapping. Test with `ha POST services/automation/trigger '{"entity_id":"automation.x","skip_condition":true}'`.

Scripts: `config/script/config/<id>` with `{"alias":..., "sequence":[...]}`.
Scenes: `config/scene/config/<id>` with `{"name":..., "entities":{...}}`.
Helpers (input_boolean, input_number, timer, ...): WebSocket `{"type":"input_boolean/create","name":"..."}`.

If you must edit YAML under `/homeassistant`, validate and reload afterwards:
`ha POST config/core/check_config` then `ha POST services/homeassistant/reload_all '{}'`
(or the specific `automation.reload`, `script.reload`, `scene.reload`). A core restart is
`ha sup POST core/restart`; the runner keeps running through it.

### Appliances (Miele and similar cloud integrations)

Appliance integrations expose status as sensors (`sensor.<appliance>_status`,
`sensor.<appliance>_program_phase`, `sensor.<appliance>_remaining_time`) and controls as
`switch.<appliance>_power`, `button.<appliance>_start`, `select.<appliance>_program`. Check what
exists for the specific appliance before promising an action; many appliances have no
"open door" control, and some cannot be powered off remotely while a program runs. Say so
plainly and offer the closest alternative (notify the phone, turn off a smart plug, etc.).

### Talk to the user's phone

`ha GET services | jq '.[] | select(.domain=="notify") | .services | keys'` lists notify
targets; `notify.mobile_app_<device>` reaches the Home Assistant companion app:
`ha POST services/notify/mobile_app_iphone '{"title":"Washer","message":"Program finished"}'`.
`persistent_notification.create` shows a notice in the Home Assistant UI.

### Diagnose

`ha GET error_log` (Core log), `ha sup GET core/logs`, `ha sup GET supervisor/info`,
`ha sup GET addons`, `ha GET config` (Core version, location, unit system, components).

## Files in this workspace

Anything you write here is kept across restarts and versioned with Git. Use it for notes about
the home (`NOTES.md`), saved automation JSON, and analysis scripts. `bin/` is restored from
the add-on on every start, so put your own scripts elsewhere; `AGENTS.md` is refreshed only
while it is unedited.
