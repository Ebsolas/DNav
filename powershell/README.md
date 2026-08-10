# PowerShell port of DNav

Windows-first folder navigation and jump aliases.

## Install location

Canonical install directory:

```
Documents\WindowsPowerShell\dnav\
```

Full path example:

```
C:\Users\<you>\Documents\WindowsPowerShell\dnav\
```

Copy the contents of this `powershell\` folder there:

```
dnav.ps1
djump.ps1
jumps
dsearch.ps1   (optional)
dfile.ps1     (optional)
README.md
```

Override with `$env:DNAV_HOME` if you install elsewhere.

### Profile hook

```powershell
. "$HOME\Documents\WindowsPowerShell\dnav\dnav.ps1"
```

Modules resolve siblings from that folder (`Get-DnavInstallDir` / `Get-DjumpPackageDir`).

## Core vs optional (EDR)

| Module | Auto-loaded | Notes |
|--------|-------------|--------|
| `dnav.ps1` | — (entry) | **Low signal:** `[Console]::ReadKey` only |
| `djump.ps1` | Yes | **Low signal:** config files + functions |
| `dsearch.ps1` | **No** | Higher signal |
| `dfile.ps1` | **No** | Higher signal |

```powershell
. "$HOME\Documents\WindowsPowerShell\dnav\dnav.ps1"
dnav
dhome
dfavorite add work
```

Optional:

```powershell
. "$HOME\Documents\WindowsPowerShell\dnav\dsearch.ps1"
. "$HOME\Documents\WindowsPowerShell\dnav\dfile.ps1"
```

## Config

| Path | Purpose |
|------|---------|
| `%APPDATA%\dnav\folders` | Bar labels |
| `%APPDATA%\dnav\config` | Brand, etc. |
| `%APPDATA%\dnav\jumps` | Jump table (seeded from install `jumps`) |
