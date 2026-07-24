# Myst — GitHub upload pack (v3.91)

## Client install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex
```

1. **First time / update:** pick `3` (Version info — shows latest release notes)
2. **Load Myst:** pick `1` (Install & Load)
3. **Unload:** pick `2`

## v3.91 SHA256 (sbscmp64_mscorwks.dll)

```
6C9CF227F8056DE2D989A0615187BAB341E8913778009BF5D17353A51557E66B
```

## v3.91 update log

- Roblox `version-9affbe66b2624d20` offsets synced from [imtheo offsets](https://offsets.imtheo.lol/offsets.hpp)
- GitHub `offsets.hpp` mirror updated for runtime fallback
- Supabase license patch v1.4.5 + bot admin RPCs redeployed
- Discord license bot restored (requires `.env` with bot token on the host)

## Build locally (when full T4 source is available)

```powershell
cd install
./build-release.ps1
```

Copies `T4/build/Myst.dll` → `sbscmp64_mscorwks.dll` and bumps `update.json`.
