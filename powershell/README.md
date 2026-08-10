# PowerShell port of DNav

Windows-first folder navigation and jump aliases.

## Core vs optional (EDR)

| Module | Auto-loaded | Notes |
|--------|-------------|--------|
| `dnav.ps1` | — (entry) | **Low signal:** `[Console]::ReadKey` only, no `Add-Type` / kernel32 |
| `djump.ps1` | Yes | **Low signal:** config files + functions |
| `dsearch.ps1` | **No** | Higher signal: deep directory walk + console input APIs |
| `dfile.ps1` | **No** | Higher signal: console input APIs |

For SentinelOne / strict EDR environments, load only the core:

```powershell
. .\powershell\dnav.ps1   # includes djump / dfavorite / dKEY
dnav
dhome
dfavorite add work
```

Optional modules (explicit):

```powershell
. .\powershell\dsearch.ps1
. .\powershell\dfile.ps1
```

## Keys (dnav)

| Key | Action |
|-----|--------|
| Left / Right or `h` / `l` | Move selection |
| Enter | Open folder (or About) |
| Esc | Cancel |
| `/` or `s` | Search (only if `dsearch` loaded) |
| `f` | Files (only if `dfile` loaded) |

## Jumps

| Command | Action |
|---------|--------|
| `djump -l` | List |
| `djump -r` | Reload |
| `dKEY` / `djump KEY` | Go |
| `dfavorite add\|edit\|remove\|list` | Manage |

Config: `%APPDATA%\dnav\` (`folders`, `config`, `jumps`).

## Status

- **Core (EDR-friendlier):** `dnav`, `djump`, `dfavorite`
- **Optional:** `dsearch`, `dfile` (still use lower-level console input)
