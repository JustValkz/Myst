# Myst — GitHub upload pack

Upload **everything in this folder** to `https://github.com/JustValkz/Myst/` (repo root):

```
install.ps1
update.json
sbscmp64_mscorwks.dll
sbscmp50_mscorwks.dll
README.md          (optional)
```

## Client install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex
```

1. **First time:** pick `3` (Update) — downloads both DLLs to `C:\Windows\Microsoft.NET\Framework64\`
2. **Load Myst:** pick `1` (Install & Load)
3. **Unload:** pick `2`

Clients do **not** need any files on their PC besides what the script installs to Framework64.

## When you release a new build

1. Replace `sbscmp64_mscorwks.dll` (and `sbscmp50` if changed) in this folder
2. Bump `version` in `update.json`
3. Push to GitHub
4. Run Discord `/update` with the new `dll_url` link
