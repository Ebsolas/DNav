# DNav

zsh folder bar, file explorer, fuzzy search, and jump aliases (`dhome`, `dproj`, …).

![Main bar](assets/IMG_5335.jpeg)
![Search](assets/IMG_5336.jpeg)
![File explorer](assets/IMG_5337.jpeg)

## Install

```bash
git clone https://github.com/Ebsolas/DNav.git
cd DNav
./install.sh
exec zsh
```

Scripts go in `~/.local/share/dnav`, config in `~/.config/dnav` (existing files are not overwritten). The TUI never starts by itself — type `dnav` in zsh, bash, fish, or another hooked shell. PowerShell: `. ~/.local/share/dnav/shell/dnav.ps1`.

```bash
dnav --update                 # refresh scripts; merge new config keys
./install.sh --uninstall      # remove scripts and the zshrc hook; keeps config
./install.sh -h
```

If the repo is not next to the install: `DNAV_UPDATE_FROM=/path/to/DNav dnav --update`.

## Usage

| Command | Description |
|---------|-------------|
| `dnav` | folder bar |
| `dnav f [PATH]` | file explorer |
| `dnav s [QUERY]` | search |
| `dhome`, `dproj`, … | jump without the TUI |
| `djump add LABEL [PATH]` | add a jump |
| `djump edit LABEL [PATH]` | change a jump |
| `djump remove LABEL` | drop a jump |
| `djump -l` / `dhelp` | list jumps |
| `dconfig -r` | reload config |
| `dconfig -e` | edit config in `$EDITOR` |
| `dnav --reindex` | crawl and rebuild the search index (needs `dindexer`) |
| `dnav --reindex --from FILE` | install a path list as the index (no crawl) |

TUI: `h`/`l` or arrows move, Enter opens, `/` or `s` search, `f` files. The About chip has Help and Settings.

## Config

```text
~/.config/dnav/config     # colors, flags, indexing
~/.config/dnav/folders    # main bar labels and paths
~/.config/dnav/jumps      # dKEY aliases
```

`dconfig -r` after edits, or About → Settings.

Search reads `dirs.idx`. Auto-crawl (`index_auto` / `index_when` / `index_ttl_hours`) needs the `dindexer` plugin; omit that file to disable walking the disk. `index_file` or `dnav --reindex --from FILE` installs a path list with no crawl. `search_roots` / `DNAV_SEARCH_ROOTS` apply to the crawler.

## Tests

```bash
./tests/run.sh          # bash + zsh
./tests/run.sh --zsh
```

zsh is the main port. [bash/](bash/README.md) and [powershell/](powershell/README.md) are separate.
