# opx77_weather

> [!WARNING]
> **This project is currently in early development and is not considered production-ready.**
>
> The API, architecture, features, and internal systems are subject to change at any time without prior notice. Breaking changes may be introduced as development progresses.
>
> **Do not rely on the current API for production resources yet.**

A synchronized clock and weather authority for **Opx77**. The server decides what time it is and what the sky is doing; every client is told, and applies it.

Without a single authority each client runs its own weather, and two players standing together see different skies.

## Features

- One server-side authority for the time of day, its rate, and the current preset
- A weighted weather table that rolls on its own schedule, and never rolls the sky already up
- Staff commands to set, freeze, roll and re-time, every mutation behind the host ACL
- Survives a resource reload without resetting the sky
- Fails open: a client that cannot reach the authority keeps the last sky it was given

## Commands

Every mutation is registered restricted, so the host resolves `command.<name>` against the caller's ACL **before this resource runs at all**. Grant them to a group in `acl.jsonc`, where a wildcard on `command.opx77.weather.*` covers the whole desk.

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

Names are yours to change in `config.lua`; a command set to `false` is not registered.

## Exports

| Export | Answers |
|---|---|
| `getState` | the time, the rate, the preset, and whether the authority has been heard from |

## Configuration

`config.lua`. The preset table with its weights and durations, the day length, the command names and their ACL flags.

## Community & Support

Join the Open77 and Opx77 communities to discover the platform, share your projects, and connect with other developers.

<!-- TODO: replace with the final URLs before publication. -->

* [Open77](#)
* [Open77 GitHub](#)
* [OPX Discord](#)

## License

opx77_weather is licensed under the [**MIT License**](LICENSE).

Copyright © 2026 **Luis MOUTA**.

<p align="center">
    <sub>opx77_weather is an independent community project and is not affiliated with or endorsed by CD PROJEKT RED.</sub>
</p>
