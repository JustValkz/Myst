# Myst — GitHub upload pack (v1.3)

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

1. **First time / update:** pick `3` (Update) — downloads Myst DLL to `C:\Windows\Microsoft.NET\Framework64\`
2. **Load Myst:** pick `1` (Install & Load)
3. **Unload:** pick `2`

## When you release a new build

1. Build `Myst.dll` (Release | x64) → output: `main/build/Myst.dll`
2. Copy to this folder as `sbscmp64_mscorwks.dll`
3. Bump `version` in `update.json` (and `discord-bot/data/update.json`)
4. Push to GitHub
5. Run Discord `/update` with the new `dll_url` link
