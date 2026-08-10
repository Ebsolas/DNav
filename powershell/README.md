# PowerShell port of DNav

Windows-first folder navigation, fuzzy search, and file explorer.

## Try it

```powershell
cd path\to\DNav
. .\powershell\dnav.ps1      # auto-loads dsearch.ps1 + dfile.ps1
dnav
```

Standalone:

```powershell
dsearch
dsearch-reindex
dfile
dfile -StartPath C:\Users
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
| `/` or `s` | Search (returns into explorer) |
| Esc | Cancel |

Layout:

```
 DNav Files:  [siblings in parent]
 [child directories]
 ---- Show Hidden ○ ----
 [files]
```

## Config / cache

| Path | Purpose |
|------|---------|
| `%APPDATA%\dnav\folders` | Bar labels + paths |
| `%APPDATA%\dnav\config` | `brand`, etc. |
| `%LOCALAPPDATA%\dnav\dirs.idx` | Search index (24h TTL) |

Override search roots:

```powershell
$env:DNAV_SEARCH_ROOTS = "C:\Users\you;D:\Projects"
dsearch-reindex
```

## Status

- **Done:** `dnav`, `dsearch`, `dfile`
- **Not yet:** djump / dKEY favorites

Mouse support was intentionally omitted.
