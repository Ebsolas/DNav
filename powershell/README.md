# PowerShell port of DNav

Windows-first folder navigation and jump aliases.

## Install location

```
Documents\WindowsPowerShell\dnav\
```

```
Documents\WindowsPowerShell\dnav\
  dnav.ps1
  djump.ps1
  jumps              # package default jump table
  dsearch.ps1        # optional
  dfile.ps1          # optional
  config\            # created on first run (user settings)
    folders
    config
    jumps
```

Override install root with `$env:DNAV_HOME`.
Override config dir with `$env:DNAV_CONFIG_DIR`.

### Profile

```powershell
. "$HOME\Documents\WindowsPowerShell\dnav\dnav.ps1"
```

## Config (no AppData)

Everything writable lives under the install tree:

| Path | Purpose |
|------|---------|
| `...\dnav\config\folders` | Bar labels + paths |
| `...\dnav\config\config` | Brand, etc. |
| `...\dnav\config\jumps` | Your jump table (`dfavorite`) |
| `...\dnav\jumps` | Package defaults (seed only) |

## Core vs optional (EDR)

| Module | Auto-loaded | Notes |
|--------|-------------|--------|
| `dnav.ps1` | — (entry) | `[Console]::ReadKey` only |
| `djump.ps1` | Yes | file I/O + functions |
| `dsearch.ps1` | No | optional, higher signal |
| `dfile.ps1` | No | optional, higher signal |
