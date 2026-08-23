# PowerShell tests

Isolated temp config. No Pester.

```powershell
pwsh -File tests/run.ps1
pwsh -File tests/run.ps1 -Filter Djump
```

or `./tests/run.sh --powershell` (skips if `pwsh` is missing).
