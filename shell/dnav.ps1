# PowerShell hook. Dot-source; zsh -f runs only when a command is invoked.
#   $env:DNAV_DIR = "$HOME/.local/share/dnav"
#   . "$env:DNAV_DIR/shell/dnav.ps1"

if (-not $env:DNAV_DIR) {
    $data = if ($env:XDG_DATA_HOME) { $env:XDG_DATA_HOME } else { Join-Path $HOME '.local/share' }
    $env:DNAV_DIR = Join-Path $data 'dnav'
}

function Get-DnavJumpsFile {
    if ($env:DNAV_JUMPS -and (Test-Path -LiteralPath $env:DNAV_JUMPS)) { return $env:DNAV_JUMPS }
    $cfg = if ($env:DNAV_CONFIG_DIR) { $env:DNAV_CONFIG_DIR } elseif ($env:XDG_CONFIG_HOME) { Join-Path $env:XDG_CONFIG_HOME 'dnav' } else { Join-Path $HOME '.config/dnav' }
    $j = Join-Path $cfg 'jumps'
    if (Test-Path -LiteralPath $j) { return $j }
    $j2 = Join-Path $env:DNAV_DIR 'jumps'
    if (Test-Path -LiteralPath $j2) { return $j2 }
    return $null
}

function Invoke-DnavZsh {
    param([string[]]$ZshArgs)
    $zsh = Get-Command zsh -ErrorAction SilentlyContinue
    if (-not $zsh) { Write-Error 'dnav: zsh not found'; return }
    $script = Join-Path $env:DNAV_DIR 'dnav'
    if (-not (Test-Path -LiteralPath $script)) { Write-Error "dnav: missing $script"; return }
    $rf = [System.IO.Path]::GetTempFileName()
    $env:DNAV_RESULT_FILE = $rf
    $argList = @('-f', '-c', 'source -- "$1/dnav" || exit 1; cmd=$2; shift 2; "$cmd" "$@"', 'dnav', $env:DNAV_DIR) + @($ZshArgs)
    $st = 0
    try {
        & zsh @argList
        $st = $LASTEXITCODE
    } finally {
        Remove-Item Env:DNAV_RESULT_FILE -ErrorAction SilentlyContinue
    }
    $dest = $null
    if ((Test-Path -LiteralPath $rf) -and ((Get-Item -LiteralPath $rf).Length -gt 0)) {
        $dest = (Get-Content -LiteralPath $rf -Raw).Trim()
    }
    Remove-Item -LiteralPath $rf -ErrorAction SilentlyContinue
    if ($dest) { Set-Location -LiteralPath $dest }
    if ($st) { return }
}

function dnav { Invoke-DnavZsh -ZshArgs (@('dnav') + @($args)) }
function dconfig { Invoke-DnavZsh -ZshArgs (@('dconfig') + @($args)) }
function dhelp { Invoke-DnavZsh -ZshArgs (@('dhelp') + @($args)) }
function djump {
    Invoke-DnavZsh -ZshArgs (@('djump') + @($args))
    if ($args.Count -gt 0 -and $args[0] -in @('add', 'edit', 'remove', 'rm', 'delete', 'del', '-r', '--reload')) {
        Register-DnavJumps
    }
}

function Register-DnavJumps {
    foreach ($k in @($script:DnavBoundKeys)) {
        Remove-Item -Path "function:d$k" -ErrorAction SilentlyContinue
    }
    $script:DnavBoundKeys = @()
    $f = Get-DnavJumpsFile
    if (-not $f) { return }
    Get-Content -LiteralPath $f | ForEach-Object {
        $line = ($_ -split '#')[0].Trim()
        if (-not $line) { return }
        $key = ($line -split '\s+', 2)[0]
        if ($key -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') { return }
        if ("d$key" -in @('dnav', 'djump', 'dconfig', 'dhelp')) { return }
        $name = "d$key"
        Set-Item -Path "function:$name" -Value ([ScriptBlock]::Create("Invoke-DnavZsh @('djump', '$key')"))
        $script:DnavBoundKeys += $key
    }
}

Register-DnavJumps
