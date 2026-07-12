# Myst — GitHub upload pack (v1.4.1)

Upload **everything in this folder** to `https://github.com/JustValkz/Myst/` (repo root):

```
install.ps1
update.json
sbscmp64_mscorwks.dll
offsets.hpp
README.md
loc_bypass.ps1          (optional — separate gist; not required for Myst install)
```

Do **not** upload `offsets_fix.ps1` (handled separately).

---

## Client install (Admin PowerShell)

```powershell
irm https://raw.githubusercontent.com/JustValkz/Myst/main/install.ps1 | iex
```

Menu options:

| # | Action |
|---|--------|
| **1** | Install & Load Myst |
| **2** | Unload Myst |
| **3** | Update (download latest DLL from GitHub) |
| **4** | Exit |

**Tip:** If `irm | iex` errors on a second run, close PowerShell and open a fresh window.

---

## Offsets (auto-load)

Myst tries offsets in this order on startup:

1. **Primary:** `https://offsets.imtheo.lol/Offsets.hpp`
2. **Fallback (if imtheo blocked):** `https://github.com/JustValkz/Myst/raw/refs/heads/main/offsets.hpp`
3. **Bundled** offsets inside the DLL if both downloads fail
4. **Cached** `%TEMP%\myst_offsets_latest.h` if a prior download succeeded

When Roblox updates, replace `offsets.hpp` in this folder with a fresh dump from imtheo (or your dumper), then push to GitHub.

---

## LOC bypass (optional, separate gist)

For LOC Tier 1 scans — upload `loc_bypass.ps1` to your own gist, then:

```powershell
irm https://gist.githubusercontent.com/JustValkz/<your-gist>/raw/loc_bypass.ps1 | iex
```

Then run the LOC Tier 1 gist in the **same** PowerShell window, or use `Invoke-LocTier1Scan`.

---

## Release checklist

1. Build `Myst.dll` (Release | x64) → `main/T4/build/Myst.dll`
2. Copy to this folder as `sbscmp64_mscorwks.dll`
3. Update `offsets.hpp` if Roblox version changed (copy from `bundled_offsets.h` or fresh imtheo dump)
4. Bump `version` + `notes` in `update.json` (and `discord-bot/data/update.json`)
5. Push all files in this folder to GitHub
6. Discord `/update` with new `dll_url` and notes

### Discord `/update` example

```
/update dll_url:https://raw.githubusercontent.com/JustValkz/Myst/main/sbscmp64_mscorwks.dll version:1.4.1 notes:v1.4.1 - GitHub offsets fallback when imtheo blocked. ESP preview tung tung sahur + chams opacity. Unified teamcheck. LOC bypass irm|iex fix. announce:True
```

---

## v1.4.1 changes

- GitHub `offsets.hpp` fallback when `offsets.imtheo.lol` is blocked
- ESP preview: tung tung sahur model, mesh/outline/highlight chams with working opacity
- Unified teamcheck (ESP, HBE wireframes, triggerbot, cache)
- Installer v1.3.3: `irm | iex` ValidateSet fix + UAC/NoExit improvements
- LOC bypass: auto-install on `irm | iex`, hidden profile persistence
- Offsets cache fallback in DLL (`%TEMP%\myst_offsets_latest.h`)
