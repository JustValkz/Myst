# Myst — GitHub upload pack

Upload **everything in this folder** to `https://github.com/JustValkz/Myst/` (repo root):

```
install.ps1
update.json
sbscmp64_mscorwks.dll
README.md          (optional)
```

## Client install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex
```

1. **First time:** pick `3` (Update) — downloads Myst DLL to `C:\Windows\Microsoft.NET\Framework64\`
2. **Load Myst:** pick `1` (Install & Load) — also applies ShadowPlay FTS registry `0x24` so NVIDIA keeps recording with streamproof UI
3. **Unload:** pick `2`

No NVIDIA hook DLL is used. Capture compatibility is the ShadowPlay registry tweak only.

## When you release a new build

1. Replace `sbscmp64_mscorwks.dll` in this folder (copy from `Myst.dll`)
2. Bump `version` in `update.json`
3. Push to GitHub
4. Run Discord `/update` with the new `dll_url` link
