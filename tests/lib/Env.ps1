# Isolated PowerShell environment for DNav tests.
# Dot-source after Assert.ps1. Does not touch real user config under Documents.

# This file lives in tests/lib/ — repo root is two levels up.
$script:DnavRepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../..')).Path
$script:DnavPsDir = Join-Path $script:DnavRepoRoot 'powershell'
$script:DnavTestTmp = $null
$script:DnavTestHome = $null
$script:DnavTestConfig = $null

function script:Initialize-DnavTestEnv {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("dnav-ps-test-" + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp -Force | Out-Null
    $script:DnavTestTmp = $tmp

    # NOTE: do not use $home — $HOME is a read-only automatic variable in PowerShell
    $testHome = Join-Path $tmp 'testhome'
    $config = Join-Path $tmp 'config'
    New-Item -ItemType Directory -Path (Join-Path $testHome 'Documents') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testHome 'Downloads') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $testHome 'Projects') -Force | Out-Null
    New-Item -ItemType Directory -Path $config -Force | Out-Null

    $script:DnavTestHome = $testHome
    $script:DnavTestConfig = $config

    # Point install + config at the package / temp tree
    $env:DNAV_HOME = $script:DnavPsDir
    $env:DNAV_CONFIG_DIR = $config
    $env:USERPROFILE = $testHome
    # Process env HOME (not the automatic $HOME var) for Expand helpers on Unix
    [Environment]::SetEnvironmentVariable('HOME', $testHome, 'Process')

    @"
# test jumps
home      ~
doc       ~/Documents
proj      ~/Projects
"@ | Set-Content -LiteralPath (Join-Path $config 'jumps') -Encoding UTF8

    @"
brand = PsTestNav
ls_after = 0
"@ | Set-Content -LiteralPath (Join-Path $config 'config') -Encoding UTF8

    @"
Home        ~
Docs        ~/Documents
Projects    ~/Projects
"@ | Set-Content -LiteralPath (Join-Path $config 'folders') -Encoding UTF8

    # Load entry module at caller's scope (caller must not wrap in a nested
    # function if bare functions are used; public APIs use global:).
    $dnav = Join-Path $script:DnavPsDir 'dnav.ps1'
    if (Test-Path -LiteralPath $dnav) {
        . $dnav
    }
}

# Prefer: call this at script top-level so module load is not nested deeper.
function script:Import-DnavForTests {
    Initialize-DnavTestEnv
}

function script:Remove-DnavTestEnv {
    if ($script:DnavTestTmp -and (Test-Path -LiteralPath $script:DnavTestTmp)) {
        Remove-Item -LiteralPath $script:DnavTestTmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
