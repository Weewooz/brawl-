# framework-starter

Bare Roblox starter built around Framework + Blink + ProfileStore + Cmdr.

Stripped of game-specific systems (UI, combat, economy). Use as a clean base for new experiences.

## Setup

```powershell
rokit install
wally install
blink
rojo sourcemap default.project.json -o sourcemap.json
wally-package-types --sourcemap sourcemap.json Packages/
wally-package-types --sourcemap sourcemap.json ServerPackages/
rojo serve
```

## What's included

| Area | Contents |
|------|----------|
| Framework | `Init` / `Start` lifecycle via `Features.lua` |
| Profile | ProfileStore + Blink Synced/Delta + stub Template |
| Networking | Blink scopes: Notifications, Latency, Profile, Reconnection |
| Systems | Profile, Notifications, Commands (Cmdr), Latency, Reconnection, Input, Cooldowns |
| Utilities | Shared helpers (Debounce, Projectiles, DynamicDestruction, …) |

## Notes

- Configure Cmdr live permissions in `src/Server/Systems/Commands/init.lua`
- Extend `src/Shared/Core/Profile/Template.lua` for your game data (do not bump `VERSION` lightly)
- `Notifications.Show` has no client toast UI yet — add one when you need it
