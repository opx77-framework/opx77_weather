# opx77_weather

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time
> without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

A synchronized clock and weather authority for **Opx77**. The server decides what time it is
and what the sky is doing; every client is told, and applies it.

Without a single authority each client runs its own weather, and two players standing together
see different skies.

## Features

- One server-side authority for the time of day, its rate, and the current preset
- A weighted weather table that rolls on its own schedule, and never rolls the sky already up
- Staff commands to set, freeze, roll and re-time, every mutation behind the host ACL
- Survives a resource reload without resetting the sky
- Fails open: a client that cannot reach the authority keeps the last sky it was given

## Requirements

The manifest declares `network.events` and `world.environment`. The environment natives are
client-side and are installed at game start: a client that joined before they existed logs a
warning and applies nothing until Cyberpunk is restarted.

Do not run the shipped `open77_weather` package alongside this one. Two authorities both hold
`world.environment`, so the clock is corrected toward two different times and the sky is
whichever authority rolled last; drop one from `resources.load` in `server.jsonc`.

## Commands

Every mutation is registered restricted, so the host resolves `command.<name>` against the
caller's ACL **before this resource runs at all**. Grant them to a group in `acl.jsonc`, where
a wildcard on `command.opx77.weather.*` covers the whole desk.

| Command | Gated |
|---|---|
| `opx77.weather` | open — the current time and sky |
| `opx77.weather.presets` | open — what is configured |
| `opx77.weather.set` | ACL |
| `opx77.weather.next` | ACL |
| `opx77.weather.freeze` | ACL |
| `opx77.weather.time` | ACL |
| `opx77.weather.time.freeze` | ACL |
| `opx77.weather.daylength` | ACL |

Names are yours to change in `config.lua`; a command set to `false` is not registered. Two
entries sharing one name would share one ACL key, so the second is refused and logged. Open
commands are rate-limited to one run every two seconds per player; the console is not limited.

The client also mirrors this resource's own command answers into the operator log, in English.
It recognises them by the names in `config.lua`, so a rename carries.

## Exports

| Export | Answers |
|---|---|
| `getState` | the time, the rate, the preset, and whether the authority has been heard from |

`getState` answers `{ ok = false, error = ... }` until the first snapshot is accepted, and on a
client with no environment natives.

## Configuration

`config.lua`. The preset table with its weights and durations, the day length, the command
names and their ACL flags, and the locale.

- `LOCALE` — which catalogue in `locales/` player-facing text is read from. `en` and `fr` ship.
- `DAY_LENGTH_MINUTES` — accepted between 1 minute and 7 days, and refused under 12 real
  minutes as faster than a client can follow; only `180` matches the engine's own rate.
- `WEATHER_FROZEN` — holds this resource's roll schedule, not the engine's own weather lock,
  which this resource keeps on for as long as it runs.
- `WEATHER` — a row with `WEIGHT = 0` is never rolled but can still be set by hand, and a row
  missing `NAME` or `PRESET` is dropped with a warning at boot. `TRANSITION_SECONDS` is clamped
  to 300, the longest crossfade a client accepts.
- A reload keeps the live time and sky; a full restart returns both to this file.

## Locales

Player-facing text lives in `locales/en.lua` and `locales/fr.lua`, keyed `weather.<thing>` and
substituting `{placeholder}` parameters. `LOCALE` in `config.lua` picks one; a key missing from
it falls back to `en`, and then to the key itself.

To add a language, copy `locales/en.lua` to `locales/<code>.lua`, change the code in the
`register` call and translate the values — every key must be present in every file. Add
`shared_script "locales/<code>.lua"` to `open77.lua` beside the others, above every file that
renders a string, then set `LOCALE = "<code>"`.

Server logs, the answers a command run from the console gets, and the error codes the exports
return stay English.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and
connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_weather is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_weather is an independent community project and is not affiliated with or
    endorsed by CD PROJEKT RED.</sub>
</p>
