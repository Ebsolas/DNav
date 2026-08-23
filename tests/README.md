# Tests

No extra deps. From the repo root:

```bash
./tests/run.sh              # bash + zsh
./tests/run.sh --zsh
./tests/run.sh --powershell # skipped if no pwsh
./tests/run.sh --all
./tests/run.sh -v
./tests/run.sh dsearch      # name filter
```

Each suite uses a temp HOME/config. dsearch uses a synthetic `dirs.idx`. Interactive TUI is not covered.

See [powershell/README.md](powershell/README.md) for the pwsh runner.
