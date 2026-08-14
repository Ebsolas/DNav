# DNav tests

Zero-dependency shell tests for **bash**, **zsh** (primary), and **PowerShell** (scaffolded).

## Run

From the repo root:

```bash
./tests/run.sh              # bash + zsh (default)
./tests/run.sh --bash       # bash only
./tests/run.sh --zsh        # zsh only
./tests/run.sh --powershell # PS (skips if no pwsh)
./tests/run.sh --all        # bash + zsh + powershell
./tests/run.sh -v           # verbose
./tests/run.sh dsearch      # filter by name
```

Single files:

```bash
bash tests/bash/test_dsearch.sh
zsh  tests/zsh/test_dsearch.zsh
pwsh -File tests/run.ps1
```

## Layout

```text
tests/
  run.sh / run.ps1
  lib/
    assert.sh / bash_env.sh      # bash
    zsh_assert.zsh / zsh_env.zsh # zsh
    Assert.ps1 / Env.ps1         # PowerShell
  bash/
    test_load.sh test_config.sh test_djump.sh test_dsearch.sh test_dfile_helpers.sh
  zsh/
    test_load.zsh test_config.zsh test_djump.zsh test_dsearch.zsh test_dfile.zsh
  powershell/
    Test-Load.ps1 Test-Djump.ps1 Test-Dsearch.Placeholder.ps1
    README.md
```

## Isolation

Each suite uses a **temp HOME + config** (or `DNAV_CONFIG_DIR` / `DNAV_HOME` for PS).  
Your real `~/.config/dnav` and Documents install tree are not modified.

dsearch tests use a **synthetic** `dirs.idx` (no full-tree `find`).

## Coverage

| Area | bash | zsh | PowerShell |
|------|------|-----|------------|
| Module load + syntax | yes | yes | yes (load) |
| Config parse / reload | yes | yes | partial |
| djump / dfavorite | yes | yes | yes |
| dsearch filter | yes | yes | placeholder |
| dfile helpers | smoke | yes (locks) | later |
| Interactive TUI | no | no | no |

## CI

- **unix** job: `./tests/run.sh` (bash + zsh) on Ubuntu  
- **powershell** job: `./tests/run.ps1` on `windows-latest`
