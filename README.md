# DNav

A zsh navigation helper: folder bar, file explorer, fuzzy search, and shell jump aliases (`dhome`, `dproj`, …).

Note: I made this for myself, I used AI heavily since it’s a personal project and I cared about rapid dev more than code quality. 

If you hate AI, cool, don’t use it.

If you like the concept and would use it except that AI was used in making it then cool, feel free to rewrite it. 

It was made for my own use, I just made it public in case someone else found it useful.

## Install

```bash
git clone https://github.com/Ebsolas/DNav.git
cd DNav
./install.sh
exec zsh          # reload shell
```

The installer will:

1. Copy scripts to `~/.local/share/dnav/` (or `$XDG_DATA_HOME/dnav`)
2. Seed config under `~/.config/dnav/` (without overwriting existing files)
3. Add a source hook to `~/.zshrc` (does **not** auto-run the TUI)

### Options

```text
./install.sh                 # default install
./install.sh --prefix DIR    # install scripts elsewhere
./install.sh --config DIR    # alternate config directory
./install.sh --no-rc         # skip .zshrc edit
./install.sh --force-config  # overwrite config/folders/jumps with defaults
./install.sh --uninstall     # remove scripts + rc hook (keeps config)
```

### Manual install

```zsh
mkdir -p ~/.local/share/dnav ~/.config/dnav
cp dnav dfile djump dsearch jumps ~/.local/share/dnav/
# then in ~/.zshrc:
source ~/.local/share/dnav/dnav
```

## Usage

| Command | What it does |
|---------|----------------|
| `dnav` | Open the navigation TUI |
| `dhelp` | List shell commands + jump aliases |
| `dconfig` / `dconfig -r` | Show/reload config |
| `dconfig -e` | Edit config files in `$EDITOR` |
| `djump -l` | List jump aliases |
| `dhome`, `dproj`, … | Jump without opening the TUI |

### In the TUI

- **←/→** or **h/l** — move on the bar  
- **Enter** — open folder / About  
- **/** or **s** — fuzzy search  
- **f** — file explorer  
- **About** chip — Help + Settings (Tab to switch; edit config in place)

## Config

```text
~/.config/dnav/config     # colors, brand, ls_after, show_hidden, …
~/.config/dnav/folders    # main bar labels + paths
~/.config/dnav/jumps      # dKEY aliases (home → dhome)
```

After editing: `dconfig -r` (or About → Settings).

`ls_after = 1` in `config` runs `ls -a` after a successful jump/select.

## Requirements

- **zsh**
- A terminal that supports common ANSI escapes
