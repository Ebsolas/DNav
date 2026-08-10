# PowerShell port of DNav

Windows-first folder navigation + fuzzy directory search.

## Try it

```powershell
cd path\to\DNav
. .\powershell\dnav.ps1      # auto-loads dsearch.ps1 if present
dnav
```

Or search directly:

```powershell
dsearch
dsearch-reindex   # force rebuild index
```

Add the dot-source line to `$PROFILE` to load on every shell.

## Keys (dnav)

| Key | Action |
|-----|--------|
| Left / Right or `h` / `l` | Move selection |
| Enter | Open folder (or About) |
| `/` or `s` | Open fuzzy search |
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

- **Done:** `dnav` bar, `dsearch` + index, About, success bar
- **Not yet:** dfile, djump / dKEY favorites

Mouse support was intentionally omitted.
