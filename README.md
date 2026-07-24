# Myst — GitHub upload pack (v3.92)

## Client install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex
```

1. **First time / update:** pick `3` (Version info)
2. **Load Myst:** pick `1` (Install & Load)
3. **Unload:** pick `2`

## v3.92 SHA256 (sbscmp64_mscorwks.dll)

```
6C9CF227F8056DE2D989A0615187BAB341E8913778009BF5D17353A51557E66B
```

## v3.92 update log

- Build output is `sbscmp64_mscorwks.dll` (no Myst.dll in install pack)
- Roblox `version-9affbe66b2624d20` offsets synced from imtheo
- Installer prefers local `T4\build\sbscmp64_mscorwks.dll` when newer than GitHub

## Auto build + GitHub publish

After any install/build change, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy-github.ps1
```

This builds `sbscmp64_mscorwks.dll`, syncs the public install pack to `Myst-repo`, commits, and pushes to GitHub. Cursor is configured to run this automatically when the agent finishes editing (`/.cursor/hooks.json`).

**Never pushed to GitHub:** `discord-bot/`, `license_patch_v145.sql`, `T4/src/`.

## Build locally (when full T4 source is available)

```powershell
cd install
./build-release.ps1
```

Produces `install\sbscmp64_mscorwks.dll` and `T4\build\sbscmp64_mscorwks.dll`.
