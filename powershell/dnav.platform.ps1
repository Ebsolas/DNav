# dnav.platform.ps1 - cross-platform helpers for DNav (Windows PS 5.1+ / pwsh 7+)
# Dot-sourced by dnav.ps1 (and usable alone). Safe to re-source.

function global:Test-DnavWindows {
    if ($null -ne (Get-Variable -Name IsWindows -ErrorAction SilentlyContinue)) {
        return [bool]$IsWindows
    }
    return ($env:OS -eq 'Windows_NT')
}

function global:Test-DnavUnix {
    return -not (Test-DnavWindows)
}

# User home directory (never assign $home — aliases automatic $HOME).
function global:Get-DnavUserHome {
    if ($env:USERPROFILE -and (Test-Path -LiteralPath $env:USERPROFILE)) {
        return $env:USERPROFILE
    }
    # Process env HOME (Unix); avoid reading automatic $HOME for assignment side-effects
    $envHome = [Environment]::GetEnvironmentVariable('HOME')
    if ($envHome -and (Test-Path -LiteralPath $envHome)) {
        return $envHome
    }
    try {
        $up = [Environment]::GetFolderPath('UserProfile')
        if ($up) { return $up }
    } catch { }
    return [Environment]::GetFolderPath('Personal')
}

function global:Expand-DnavUserPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq '-') { return $null }
    $userHome = Get-DnavUserHome
    if ($Path -eq '~') { return $userHome }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return (Join-Path $userHome $Path.Substring(2))
    }
    $expanded = [Environment]::ExpandEnvironmentVariables($Path)
    if ([System.IO.Path]::IsPathRooted($expanded)) {
        try { return [System.IO.Path]::GetFullPath($expanded) } catch { return $expanded }
    }
    try {
        return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $expanded))
    } catch {
        return (Join-Path (Get-Location).Path $expanded)
    }
}

function global:Get-DnavDefaultInstallDir {
    if ($env:DNAV_HOME -and (Test-Path -LiteralPath $env:DNAV_HOME)) {
        return [System.IO.Path]::GetFullPath($env:DNAV_HOME)
    }
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
        if ($here) { return $here }
    }
    $userHome = Get-DnavUserHome
    if (Test-DnavWindows) {
        $docs = [Environment]::GetFolderPath('MyDocuments')
        if (-not $docs) { $docs = Join-Path $userHome 'Documents' }
        # Prefer PowerShell 7 profile tree, then WindowsPowerShell
        $candidates = @(
            (Join-Path $docs 'PowerShell\dnav')
            (Join-Path $docs 'WindowsPowerShell\dnav')
        )
        foreach ($c in $candidates) {
            if (Test-Path -LiteralPath $c) { return $c }
        }
        return $candidates[0]
    }
    # Linux / macOS: XDG data home sibling
    $data = $env:XDG_DATA_HOME
    if (-not $data) { $data = Join-Path $userHome '.local/share' }
    return (Join-Path $data 'dnav-ps')
}

function global:Get-DnavDefaultConfigDir {
    if ($env:DNAV_CONFIG_DIR) { return $env:DNAV_CONFIG_DIR }
    # Share XDG config with zsh/bash on Unix when possible
    if (Test-DnavUnix) {
        $xdg = $env:XDG_CONFIG_HOME
        if (-not $xdg) {
            $xdg = Join-Path (Get-DnavUserHome) '.config'
        }
        return (Join-Path $xdg 'dnav')
    }
    # Windows drop-in: config under install tree
    $install = if ($global:DnavInstallDir) { $global:DnavInstallDir } else { Get-DnavDefaultInstallDir }
    return (Join-Path $install 'config')
}

function global:Get-DnavCacheDir {
    if ($env:DNAV_CACHE_DIR) { return $env:DNAV_CACHE_DIR }
    if ($env:XDG_CACHE_HOME) { return (Join-Path $env:XDG_CACHE_HOME 'dnav') }
    if (Test-DnavWindows -and $env:LOCALAPPDATA) {
        return (Join-Path $env:LOCALAPPDATA 'dnav')
    }
    $userHome = Get-DnavUserHome
    return (Join-Path $userHome '.cache/dnav')
}

# Portable key read — works on Windows and Linux pwsh TTYs.
# Returns: Key (ConsoleKey), Char, Ctrl (bool)
function global:Read-DnavKey {
    $ki = [Console]::ReadKey($true)
    $ctrl = $false
    try {
        $ctrl = ($ki.Modifiers -band [ConsoleModifiers]::Control) -ne 0
    } catch { }
    return [pscustomobject]@{
        Key     = $ki.Key
        Char    = $ki.KeyChar
        Ctrl    = $ctrl
        KeyInfo = $ki
    }
}

function global:Get-DnavConsoleWidth {
    try {
        $w = [Console]::WindowWidth
        if ($w -lt 20) { return 80 }
        return $w
    } catch {
        return 80
    }
}

function global:Invoke-DnavWithHiddenCursor {
    param([scriptblock]$Script)
    $prev = $true
    try {
        $prev = [Console]::CursorVisible
        [Console]::CursorVisible = $false
    } catch { }
    try {
        & $Script
    } finally {
        try { [Console]::CursorVisible = $prev } catch { }
    }
}
