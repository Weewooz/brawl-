# Brawl

Roblox Katana and Yumi combat, Capture matches, and dungeons built around Framework, Blink, ProfileStore, and Cmdr.

## Setup

```powershell
rokit install
wally install
blink network.blink
rojo sourcemap default.project.json -o sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/
wally-package-types --sourcemap sourcemap.json ServerPackages/
rojo serve
```

Connect the Studio Rojo plugin to `localhost:34872`, then press Play.

## What's included

- `src/Client`: input, camera, combat presentation, and UI.
- `src/Server`: combat authority, Capture, dungeons, profiles, and commands.
- `src/Shared`: framework, rules, networking, and utilities.
- `src/Assets`: authored models, UI, effects, and audio.
- `network.blink`: network contracts; `default.project.json`: Rojo mapping.

## Notes

- Register systems in `src/Shared/Core/Framework/Features.lua`.
- Keep specs beneath their tested module: `Name/init.lua` and `Name/Name.spec.lua`.
- Author assets in Studio Edit mode via MCP, export to `src/Assets`, and clone templates at runtime.
- Local checks, outputs, builds, and task notes are ignored by Git.
