# Myst — GitHub upload pack (v2.9)

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

1. Replace `sbscmp64_mscorwks.dll` in this folder (copy from `T4\build\Myst.dll`)
2. Bump `version` in `update.json`
3. Push to GitHub
4. Run Discord `/update` with the new `dll_url` link

## v2.9 SHA256 (sbscmp64_mscorwks.dll)

```
A5FC739CCC619C86DDF0C39E8880D41B21772D9833CE9413C87B82C9C0BD140D
```
