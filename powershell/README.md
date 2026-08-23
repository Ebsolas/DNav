# PowerShell port

Windows PowerShell 5.1+, PowerShell 7, and `pwsh` on Linux/macOS.

## Install

**Linux / macOS:** copy `powershell/` to `~/.local/share/dnav-ps` and dot-source from your profile:

```powershell
. "$HOME/.local/share/dnav-ps/dnav.ps1"
```

Config is XDG, shared with zsh when present: `~/.config/dnav/`.

**Windows:** put the folder at `Documents\PowerShell\dnav\` (or `Documents\WindowsPowerShell\dnav\` for 5.1) and:

```powershell
. "$HOME\Documents\PowerShell\dnav\dnav.ps1"
```

Config then lives under that tree (or `$env:DNAV_CONFIG_DIR`).

| Variable | |
|----------|-|
| `DNAV_HOME` | scripts |
| `DNAV_CONFIG_DIR` | config |
| `DNAV_CACHE_DIR` | search index |
| `DNAV_SEARCH_ROOTS` | `;` or `,` separated roots |
| `DNAV_JUMPS` | jumps file |

Default search is home-only, depth 8, capped at 20 000 paths. `dsearch-reindex` rebuilds.

Stay 5.1-safe: no ternary/`??`/pipeline `&&`, never assign `$home`.

```bash
./tests/run.sh --powershell
pwsh -File tests/run.ps1
```
