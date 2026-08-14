# Load + public surface (PowerShell)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here '..\lib\Assert.ps1')
. (Join-Path $here '..\lib\Env.ps1')

try {
    Initialize-DnavTestEnv

    Run-Test 'package files exist' {
        Assert-File (Join-Path $script:DnavPsDir 'dnav.ps1')
        Assert-File (Join-Path $script:DnavPsDir 'dnav.platform.ps1')
        Assert-File (Join-Path $script:DnavPsDir 'djump.ps1')
        Assert-File (Join-Path $script:DnavPsDir 'dsearch.ps1')
        Assert-File (Join-Path $script:DnavPsDir 'dfile.ps1')
        Assert-File (Join-Path $script:DnavPsDir 'jumps')
    }

    Run-Test 'public commands defined' {
        Assert-True ($null -ne (Get-Command dnav -ErrorAction SilentlyContinue)) 'dnav'
        Assert-True ($null -ne (Get-Command dhelp -ErrorAction SilentlyContinue)) 'dhelp'
        Assert-True ($null -ne (Get-Command djump -ErrorAction SilentlyContinue)) 'djump'
        Assert-True ($null -ne (Get-Command dfavorite -ErrorAction SilentlyContinue)) 'dfavorite'
        Assert-True ($null -ne (Get-Command dsearch -ErrorAction SilentlyContinue)) 'dsearch'
        Assert-True ($null -ne (Get-Command dfile -ErrorAction SilentlyContinue)) 'dfile'
        Assert-True ($null -ne (Get-Command Get-DnavUserHome -ErrorAction SilentlyContinue)) 'Get-DnavUserHome'
        Assert-True ($null -ne (Get-Command Read-DnavKey -ErrorAction SilentlyContinue)) 'Read-DnavKey'
    }

    Run-Test 'config dir isolated' {
        $cfg = Get-DnavConfigDir
        Assert-Eq $cfg $script:DnavTestConfig 'DNAV_CONFIG_DIR'
        Assert-Dir $cfg
    }

    Run-Test 'install dir points at package' {
        $inst = Get-DnavInstallDir
        Assert-True (Test-Path -LiteralPath (Join-Path $inst 'dnav.ps1')) "install has dnav.ps1 ($inst)"
    }

    Run-Test 'path expand cross-platform' {
        $uh = Get-DnavUserHome
        Assert-Eq (Expand-DnavUserPath '~') $uh 'expand ~'
        $docs = Expand-DnavUserPath '~/Documents'
        Assert-Eq $docs (Join-Path $uh 'Documents') 'expand ~/Documents'
    }

    Run-Test 'platform detection' {
        Assert-True ((Test-DnavWindows) -xor (Test-DnavUnix)) 'exactly one of Windows/Unix'
    }
}
finally {
    Remove-DnavTestEnv
}

Dnav-TestFinish
