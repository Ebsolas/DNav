#!/usr/bin/env pwsh
# DNav PowerShell test runner (zero Pester dependency).
#
# Usage:
#   pwsh -File tests/run.ps1
#   pwsh -File tests/run.ps1 -VerboseTests
#   ./tests/run.sh --powershell   # from bash runner if pwsh available
#
param(
    [switch]$VerboseTests,
    [string[]]$Filter = @()
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
if (-not $Root) { $Root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path }
Set-Location $Root

if ($VerboseTests) { $env:DNAV_TEST_VERBOSE = '1' }

$pass = 0; $fail = 0; $skip = 0
$filesRun = 0; $filesFail = 0

Write-Host "DNav PowerShell tests  (repo: $Root)"
Write-Host ("pwsh " + $PSVersionTable.PSVersion)

$dir = Join-Path $Root 'tests/powershell'
$scripts = Get-ChildItem -LiteralPath $dir -Filter 'Test-*.ps1' | Sort-Object Name
if ($Filter.Count -gt 0) {
    $scripts = $scripts | Where-Object {
        $n = $_.Name
        $Filter | Where-Object { $n -like "*$_*" } | Select-Object -First 1
    }
}

foreach ($script in $scripts) {
    $filesRun++
    Write-Host ""
    Write-Host "==> tests/powershell/$($script.Name) (pwsh)"
    $out = & pwsh -NoProfile -File $script.FullName 2>&1 | Out-String
    $rc = $LASTEXITCODE
    if ($out) { Write-Host $out.TrimEnd() }

    if ($out -match '# dnav-test: pass=(\d+) fail=(\d+) skip=(\d+)') {
        $pass += [int]$Matches[1]
        $fail += [int]$Matches[2]
        $skip += [int]$Matches[3]
    }
    if ($rc -ne 0) {
        $filesFail++
        if ($out -notmatch '# dnav-test:') { $fail++ }
        Write-Host "  ** file exit $rc" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "========================================"
Write-Host "Files: $filesRun  failed-files: $filesFail"
Write-Host "Assertions: pass=$pass  fail=$fail  skip=$skip"
Write-Host "========================================"

if ($fail -gt 0 -or $filesFail -gt 0) { exit 1 }
exit 0
