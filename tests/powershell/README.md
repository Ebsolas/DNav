# PowerShell tests

Scaffold for the Windows PowerShell port. Same idea as the bash/zsh suites:
isolated temp config, pure helpers first, TUI later.

## Requirements

- PowerShell 7+ (`pwsh`) recommended  
  Windows PowerShell 5.1 may work but is not CI-primary.

## Run

```powershell
# from repo root
pwsh -File tests/run.ps1
pwsh -File tests/run.ps1 -VerboseTests
pwsh -File tests/run.ps1 -Filter Djump
```

Or from the bash runner (skips if `pwsh` is missing):

```bash
./tests/run.sh --powershell
./tests/run.sh --all          # bash + zsh + powershell (if available)
```

## Layout

```text
tests/
  run.ps1                      # PS runner
  lib/
    Assert.ps1                 # Assert-Eq, Run-Test, Dnav-TestFinish
    Env.ps1                    # temp DNAV_HOME / DNAV_CONFIG_DIR + dot-source
  powershell/
    Test-Load.ps1              # package load + public commands
    Test-Djump.ps1             # labels, expand, import, dfavorite
    Test-Dsearch.Placeholder.ps1
    README.md                  # this file
```

No Pester required. Files print `# dnav-test: pass=N fail=N skip=N` for the runners.

## Adding tests later

1. Copy `Test-Djump.ps1` → `Test-Dsearch.ps1`
2. Dot-source `dsearch.ps1` in `Env.ps1` (or only in that file)
3. Prefer pure functions (`Expand-*`, filter helpers) over `ReadKey` loops
4. Keep config under `$env:DNAV_CONFIG_DIR` temp dir from `Initialize-DnavTestEnv`

## CI

`.github/workflows/test.yml` has a `powershell` job on `windows-latest`.
Linux jobs skip PS unless `pwsh` is installed.
