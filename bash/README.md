# Bash port of DNav

These are bash rewrites of the zsh modules.

| File | Role |
|------|------|
| `dnav` | Main navigation TUI |
| `dfile` | File explorer |
| `djump` | Jump table + `dKEY` commands + `dfavorite` |
| `dsearch` | Fuzzy directory search |
| `jumps` | Default jump table |

**Status:** Working ports of core behavior. The bash `dnav` About view is simplified vs zsh (no full in-TUI settings editor). Search indexing, jumps, explorer, and main bar match the zsh UX.

**Requirements:** bash 4+, a terminal with ANSI support.

To try without the root installer:

```bash
source bash/dnav   # loads djump/dfile/dsearch if present
dnav
```

A future `install.sh --shell bash` (or `bash/install.sh`) can install these the same way the zsh package is installed today.
