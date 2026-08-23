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
| `dnav --reindex` | rebuild the search index |
| `dnav --reindex --from FILE` | install a path list as the index |

TUI: `h`/`l` or arrows move, Enter opens, `/` or `s` search, `f` files. The About chip has Help and Settings.

## Config

```text
~/.config/dnav/config     # colors, flags, indexing
~/.config/dnav/folders    # main bar labels and paths
~/.config/dnav/jumps      # dKEY aliases
```

`dconfig -r` after edits, or About → Settings.

Search indexes `$HOME` unless `search_roots` / `DNAV_SEARCH_ROOTS` is set. `index_auto`, `index_when`, and `index_ttl_hours` control rebuilds; `index_auto = 0` means only `dnav --reindex`.

## Tests

```bash
./tests/run.sh          # bash + zsh
./tests/run.sh --zsh
```

zsh is the main port. [bash/](bash/README.md) and [powershell/](powershell/README.md) are separate.
