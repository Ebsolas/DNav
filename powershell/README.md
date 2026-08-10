# PowerShell port of DNav

Windows-first folder navigation bar.

## Try it

```powershell
cd path\to\DNav
. .\powershell\dnav.ps1
dnav
```

To load on every shell, add the dot-source line to your `$PROFILE`.

## Keys

| Key | Action |
|-----|--------|
| Left / Right or `h` / `l` | Move selection |
| Enter | Open folder (or About) |
| Esc | Cancel |

## Config

Created on first run under `%APPDATA%\dnav` (or `$env:DNAV_CONFIG_DIR`):

- `folders` - bar labels and paths (`Label  Path`, `~` expands)
- `config` - `brand = DNav`, etc.

## Status

- **Done:** `dnav` folder bar, config, About, success path bar, keyboard only
- **Not yet:** dfile, dsearch, djump / dKEY favorites

Mouse support from the original prototype was dropped on purpose.
