# Myst — GitHub upload pack

## Private (DLL) — `sbscmp64_mscorwks.dll`

Admin PowerShell:

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex
```

1. **First time / update:** pick `3` (Version info)
2. **Load Myst:** pick `1` (Install & Load)
3. **Unload:** pick `2`

## Public (EXE) — `AutoClicker-3.0.exe`

PowerShell:

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install-public.ps1 | iex
```

Downloads the signed EXE to **Downloads**, trusts the **Wndws** publisher cert, verifies the signature, and launches.

## Auto build + GitHub publish

After any install/build change, run:

```powershell
powershell -ExecutionPolicy Bypass -File .\deploy-github.ps1
```

**Private build** (`build-release.ps1`) → `sbscmp64_mscorwks.dll`  
**Public build** (`build-public.ps1`) → `AutoClicker-3.0.exe`

**Never pushed to GitHub:** `discord-bot/`, `license_patch_v145.sql`, `T4/src/`.
