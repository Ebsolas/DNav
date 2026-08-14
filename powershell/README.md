# PowerShell port of DNav (cross-platform)

Works on **Windows PowerShell 5.1+**, **PowerShell 7+ on Windows**, and **`pwsh` on Linux/macOS**.

## Install

### Linux / macOS (`pwsh`)

```powershell
# From the DNav repo (or copy powershell/ somewhere permanent)
$env:DNAV_HOME = "$HOME/.local/share/DNav/powershell"   # example: clone path
# Recommended long-term:
#   cp -a powershell ~/.local/share/dnav-ps
#   $env:DNAV_HOME = "$HOME/.local/share/dnav-ps"

# Profile (~/.config/powershell/Microsoft.PowerShell_profile.ps1):
if (Test-Path "$env:DNAV_HOME/dnav.ps1") {
    . "$env:DNAV_HOME/dnav.ps1"
} elseif (Test-Path "$HOME/.local/share/dnav-ps/dnav.ps1") {
    . "$HOME/.local/share/dnav-ps/dnav.ps1"
} elseif (Test-Path "$HOME/.local/share/DNav/powershell/dnav.ps1") {
    . "$HOME/.local/share/DNav/powershell/dnav.ps1"
}
```

Config defaults to **XDG** (shared with zsh/bash when present):

```text
~/.config/dnav/{config,folders,jumps}
~/.cache/dnav/dirs.idx          # dsearch index
```

### Windows

Drop the `powershell/` folder at:

```text
Documents\PowerShell\dnav\          # preferred (pwsh)
  or
Documents\WindowsPowerShell\dnav\   # Windows PowerShell 5.1
```

```powershell
. "$HOME\Documents\PowerShell\dnav\dnav.ps1"
```

Config lives under the install tree: `...\dnav\config\` (or set `$env:DNAV_CONFIG_DIR`).

## Environment

| Variable | Purpose |
|----------|---------|
| `DNAV_HOME` | Package directory (scripts) |
| `DNAV_CONFIG_DIR` | Override config directory |
| `DNAV_CACHE_DIR` | Override dsearch index directory |
| `DNAV_SEARCH_ROOTS` | `;` or `,` separated index roots |
| `DNAV_SEARCH_BROAD` | `1` = also index /opt, extra drives (off by default) |
| `DNAV_SEARCH_MAX_DEPTH` | Directory walk depth (default **8**) |
| `DNAV_SEARCH_MAX_PATHS` | Cap index size (default **20000**) |
| `DNAV_JUMPS` | Override jumps file path |

**Search performance:** default is **home only**, depth-limited, path-capped. Rebuild after upgrades:

```powershell
Remove-Item "$env:HOME/.cache/dnav/dirs.idx" -ErrorAction SilentlyContinue
dsearch-reindex
```

## Modules

| File | Role | Auto-loaded |
|------|------|-------------|
| `dnav.platform.ps1` | OS/home/paths/ReadKey | via dnav |
| `dnav.ps1` | Main bar TUI | entry |
| `djump.ps1` | jumps + `dfavorite` + `dKEY` | yes |
| `dsearch.ps1` | fuzzy search | yes if present |
| `dfile.ps1` | file explorer | yes if present |
| `jumps` | package default jump table | seed only |

## PS 5.1 vs 7 guidelines

- No ternary / `??` / pipeline `&&` (5.1-safe)
- Never assign **`$home`** (aliases automatic `$HOME`)
- Use `Get-DnavUserHome` / `Expand-DnavUserPath` for paths
- Console input via `[Console]::ReadKey` (not kernel32) so Linux works

## Commands

| Command | What it does |
|---------|----------------|
| `dnav` | Folder bar |
| `dsearch` | Fuzzy directory search |
| `dfile` | Mini explorer |
| `djump` / `dhome`… | Jump aliases |
| `dfavorite` | Manage jumps |
| `dhelp` | Help |
| `dsearch-reindex` | Rebuild search index |

## Tests

```bash
./tests/run.sh --powershell
# or
pwsh -File tests/run.ps1
```
