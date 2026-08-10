# PowerShell port of DNav

Windows-first folder navigation, fuzzy search, file explorer, and jump aliases.

## Try it

```powershell
cd path\to\DNav
. .\powershell\dnav.ps1      # loads dsearch, dfile, djump
dnav
```

```powershell
dhome                 # jump alias
djump -l              # list
dfavorite add work C:\Projects\work
dsearch
dfile
```

Add the dot-source line to `$PROFILE` to load on every shell.

## Keys (dnav)

| Key | Action |
|-----|--------|
| Left / Right or `h` / `l` | Move selection |
| Enter | Open folder (or About) |
| `/` or `s` | Fuzzy directory search |
| `f` | File explorer |
| Esc | Cancel |

## Keys (dsearch)

| Key | Action |
|-----|--------|
| Type | Filter directories |
| Up / Down or Ctrl+P / Ctrl+N | Move selection |
| Enter | Jump to folder |
| Backspace | Delete character |
| Ctrl+U | Clear query |
| Esc | Cancel |

## Keys (dfile)

| Key | Action |
|-----|--------|
| Left / Right or `h` / `l` | Move on current row |
| Up / `k` | Go to parent |
| Down / `j` | Enter selected subdirectory |
| Tab or `f` | Toggle focus: dirs ↔ files |
| `.` | Toggle show hidden |
| Enter | Exit to dir, or open file |
| `/` or `s` | Search |
| Esc | Cancel |

## Jumps (`djump` / `dfavorite`)

| Command | Action |
|---------|--------|
| `djump -l` | List aliases |
| `djump -r` | Reload from disk |
| `djump KEY` or `dKEY` | `cd` to jump |
| `dfavorite add LABEL [PATH]` | Add (default path: `$PWD`) |
| `dfavorite edit LABEL [PATH]` | Update path |
| `dfavorite remove LABEL` | Remove |
| `dfavorite list` | List |

User file: `%APPDATA%\dnav\jumps` (seeded from package `powershell\jumps` on first run).

## Config / cache

| Path | Purpose |
|------|---------|
| `%APPDATA%\dnav\folders` | Bar labels + paths |
| `%APPDATA%\dnav\config` | `brand`, etc. |
| `%APPDATA%\dnav\jumps` | Jump table |
| `%LOCALAPPDATA%\dnav\dirs.idx` | Search index (24h TTL) |

```powershell
$env:DNAV_SEARCH_ROOTS = "C:\Users\you;D:\Projects"
dsearch-reindex
```

## Status

- **Done:** `dnav`, `dsearch`, `dfile`, `djump` / `dKEY` / `dfavorite`
- Mouse support was intentionally omitted.
