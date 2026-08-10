# dnav.ps1 - folder navigation bar for PowerShell (Windows)
#
# SentinelOne-friendly core: no Add-Type, no kernel32 P/Invoke.
# Keyboard via [Console]::ReadKey only. Optional modules (dfile/dsearch)
# are NOT auto-loaded — they use lower-level console APIs and may be noisier.
#
# Dot-source:
#   . .\powershell\dnav.ps1          # loads djump/dfavorite automatically
#   . .\powershell\dsearch.ps1       # optional, higher EDR signal
#   . .\powershell\dfile.ps1         # optional, higher EDR signal
#
# Keys: Left/Right or h/l  move | Enter open | Esc cancel
#       / or s  search (if dsearch loaded) | f  files (if dfile loaded)

# Auto-load only djump (low signal: file I/O + functions, no P/Invoke)
$__dnavDir = $PSScriptRoot
if (-not $__dnavDir -and $MyInvocation.MyCommand.Path) {
    $__dnavDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}
if ($__dnavDir) {
    $__djumpPath = Join-Path $__dnavDir 'djump.ps1'
    if ((Test-Path -LiteralPath $__djumpPath) -and -not (Get-Command djump -ErrorAction SilentlyContinue)) {
        . $__djumpPath
    }
}

function Get-DnavConfigDir {
    if ($env:DNAV_CONFIG_DIR) { return $env:DNAV_CONFIG_DIR }
    if ($env:XDG_CONFIG_HOME) { return (Join-Path $env:XDG_CONFIG_HOME 'dnav') }
    return (Join-Path $env:APPDATA 'dnav')
}

function Initialize-DnavConfig {
    $dir = Get-DnavConfigDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $foldersFile = Join-Path $dir 'folders'
    if (-not (Test-Path -LiteralPath $foldersFile)) {
        @"
# Main dnav bar - Label  Path  (one per line)
# Paths may use ~ for `$HOME / `$env:USERPROFILE
Home        ~
Docs        ~/Documents
Down        ~/Downloads
Pics        ~/Pictures
Desktop     ~/Desktop
Music       ~/Music
Videos      ~/Videos
Config      ~/.config
"@ | Set-Content -LiteralPath $foldersFile -Encoding UTF8
    }

    $configFile = Join-Path $dir 'config'
    if (-not (Test-Path -LiteralPath $configFile)) {
        @"
# DNav settings
brand = DNav
ls_after = 0
"@ | Set-Content -LiteralPath $configFile -Encoding UTF8
    }
}

function Expand-DnavPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq '-') { return $null }
    if ($Path -eq '~') {
        return $env:USERPROFILE
    }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return (Join-Path $env:USERPROFILE $Path.Substring(2))
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-DnavFolders {
    Initialize-DnavConfig
    $foldersFile = Join-Path (Get-DnavConfigDir) 'folders'
    $list = @()

    if (Test-Path -LiteralPath $foldersFile) {
        Get-Content -LiteralPath $foldersFile -ErrorAction SilentlyContinue | ForEach-Object {
            $line = ($_ -split '#')[0].Trim()
            if (-not $line) { return }
            $parts = $line -split '\s+', 2
            if ($parts.Count -lt 2) { return }
            $label = $parts[0]
            $path = Expand-DnavPath $parts[1]
            if (-not $path) { return }
            if ($label -match '^(?i)(help|about)$') { return }
            $list += [pscustomobject]@{ Name = $label; Path = $path }
        }
    }

    if ($list.Count -eq 0) {
        $list = @(
            [pscustomobject]@{ Name = 'Home';    Path = $env:USERPROFILE }
            [pscustomobject]@{ Name = 'Docs';    Path = [Environment]::GetFolderPath('MyDocuments') }
            [pscustomobject]@{ Name = 'Down';    Path = (Join-Path $env:USERPROFILE 'Downloads') }
            [pscustomobject]@{ Name = 'Pics';    Path = [Environment]::GetFolderPath('MyPictures') }
            [pscustomobject]@{ Name = 'Desktop'; Path = [Environment]::GetFolderPath('Desktop') }
            [pscustomobject]@{ Name = 'Music';   Path = [Environment]::GetFolderPath('MyMusic') }
            [pscustomobject]@{ Name = 'Videos';  Path = [Environment]::GetFolderPath('MyVideos') }
        )
    }

    $list += [pscustomobject]@{ Name = 'About'; Path = $null }
    return $list
}

function Get-DnavBrand {
    $configFile = Join-Path (Get-DnavConfigDir) 'config'
    $brand = 'DNav'
    if (Test-Path -LiteralPath $configFile) {
        Get-Content -LiteralPath $configFile -ErrorAction SilentlyContinue | ForEach-Object {
            $line = ($_ -split '#')[0].Trim()
            if ($line -match '^\s*brand\s*=\s*(.+)$') {
                $brand = $Matches[1].Trim().Trim('"', "'")
            }
        }
    }
    return $brand
}

function Show-DnavSuccessBar {
    param([string]$Path)
    $w = [Math]::Max(20, [Console]::WindowWidth)
    $display = $Path
    if ($display.Length -gt $w) {
        $display = $display.Substring(0, $w - 1) + [char]0x2026
    }
    Write-Host ($display.PadRight($w)) -ForegroundColor Black -BackgroundColor Cyan
}

function Show-DnavAbout {
    Write-Host ''
    Write-Host ' DNav About ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host ''
    Write-Host '  Left/Right or h/l   move on the bar'
    Write-Host '  Enter               open selected folder'
    Write-Host '  Enter on About      this help'
    Write-Host '  Esc                 cancel / leave'
    if (Get-Command dsearch -ErrorAction SilentlyContinue) {
        Write-Host '  / or s              fuzzy directory search (optional module)'
    }
    if (Get-Command dfile -ErrorAction SilentlyContinue) {
        Write-Host '  f                   file explorer (optional module)'
    }
    Write-Host '  dKEY / djump        jump aliases (dfavorite to manage)'
    Write-Host '  Config dir          ' -NoNewline
    Write-Host (Get-DnavConfigDir) -ForegroundColor DarkGray
    Write-Host ''
}

function dnav {
    # No Add-Type / kernel32 — use managed [Console]::ReadKey only.
    $items = @(Get-DnavFolders)
    $brand = Get-DnavBrand
    $selected = 0
    $hasSearch = [bool](Get-Command dsearch -ErrorAction SilentlyContinue)
    $hasFiles  = [bool](Get-Command dfile -ErrorAction SilentlyContinue)

    try {
        $currentPath = [System.IO.Path]::GetFullPath((Get-Location).Path)
        for ($i = 0; $i -lt $items.Count; $i++) {
            if (-not $items[$i].Path) { continue }
            try {
                $p = [System.IO.Path]::GetFullPath($items[$i].Path)
                if ($p -eq $currentPath) { $selected = $i; break }
            } catch { }
        }
    } catch {
        $selected = 0
    }

    if ([Console]::BufferHeight -lt 3) {
        Write-Host 'Console buffer too small for dnav.' -ForegroundColor Red
        return
    }

    [Console]::WriteLine()
    [Console]::WriteLine()
    $startRow = [Console]::CursorTop - 2

    function Clear-Bar {
        $winW = [Console]::WindowWidth
        for ($r = 0; $r -lt 3; $r++) {
            [Console]::SetCursorPosition(0, $startRow + $r)
            [Console]::Write((' ' * $winW))
        }
        [Console]::SetCursorPosition(0, $startRow)
    }

    function Redraw {
        $winW = [Console]::WindowWidth
        [Console]::SetCursorPosition(0, $startRow)
        $header = " $brand "
        Write-Host $header -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        $hintParts = @('h/l arrows', 'Enter')
        if ($hasSearch) { $hintParts += '/ search' }
        if ($hasFiles)  { $hintParts += 'f files' }
        $hintParts += 'Esc'
        $hint = '  (' + ($hintParts -join '  ') + ')'
        Write-Host $hint -ForegroundColor DarkGray -NoNewline
        $clearLen = $winW - [Console]::CursorLeft
        if ($clearLen -gt 0) { [Console]::Write((' ' * $clearLen)) }

        [Console]::SetCursorPosition(0, $startRow + 1)
        [Console]::Write((' ' * $winW))

        $col = 1
        for ($i = 0; $i -lt $items.Count; $i++) {
            $name = $items[$i].Name
            if (($col + $name.Length + 2) -ge $winW) { break }
            [Console]::SetCursorPosition($col, $startRow + 1)
            if ($i -eq $selected) {
                Write-Host (" $name ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            } else {
                Write-Host (" $name ") -NoNewline
            }
            $col += $name.Length + 3
        }
        [Console]::SetCursorPosition(0, $startRow + 2)
    }

    function Navigate-Selected {
        $item = $items[$selected]
        if (-not $item.Path) {
            Clear-Bar
            Show-DnavAbout
            return
        }
        $path = $item.Path
        if (Test-Path -LiteralPath $path -PathType Container) {
            Set-Location -LiteralPath $path
            $full = (Get-Location).Path
            Clear-Bar
            Show-DnavSuccessBar $full
        } else {
            Write-Host "`nFolder not found: $path" -ForegroundColor Red
        }
    }

    $prevVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        Redraw

        while ($true) {
            $keyInfo = [Console]::ReadKey($true)
            $key = $keyInfo.Key
            $ch = $keyInfo.KeyChar

            switch ($key) {
                ([ConsoleKey]::LeftArrow) {
                    if ($selected -gt 0) { $selected--; Redraw }
                }
                ([ConsoleKey]::RightArrow) {
                    if ($selected -lt ($items.Count - 1)) { $selected++; Redraw }
                }
                ([ConsoleKey]::Enter) {
                    Navigate-Selected
                    return
                }
                ([ConsoleKey]::Escape) {
                    Clear-Bar
                    return
                }
                default {
                    if ($ch -eq 'h' -or $ch -eq 'H') {
                        if ($selected -gt 0) { $selected--; Redraw }
                    }
                    elseif ($ch -eq 'l' -or $ch -eq 'L') {
                        if ($selected -lt ($items.Count - 1)) { $selected++; Redraw }
                    }
                    elseif (($ch -eq '/' -or $ch -eq 's' -or $ch -eq 'S') -and $hasSearch) {
                        Clear-Bar
                        $navigated = dsearch
                        if ($navigated) { return }
                        [Console]::WriteLine()
                        [Console]::WriteLine()
                        $startRow = [Console]::CursorTop - 2
                        Redraw
                    }
                    elseif (($ch -eq 'f' -or $ch -eq 'F') -and $hasFiles) {
                        Clear-Bar
                        $fpath = $null
                        $item = $items[$selected]
                        if ($item.Path -and (Test-Path -LiteralPath $item.Path -PathType Container)) {
                            $fpath = $item.Path
                        }
                        if (-not $fpath) { $fpath = (Get-Location).Path }
                        $navigated = dfile -StartPath $fpath
                        if ($navigated) { return }
                        [Console]::WriteLine()
                        [Console]::WriteLine()
                        $startRow = [Console]::CursorTop - 2
                        Redraw
                    }
                }
            }
        }
    }
    finally {
        [Console]::CursorVisible = $prevVisible
    }
}

function dhelp {
    Write-Host 'DNav (PowerShell) - core' -ForegroundColor Cyan
    Write-Host '  dnav              open the folder bar'
    Write-Host '  djump / dKEY      jump aliases'
    Write-Host '  dfavorite         manage jumps'
    Write-Host '  dhelp             this text'
    Write-Host ''
    Write-Host 'Optional (higher EDR signal - load only if needed):' -ForegroundColor DarkYellow
    Write-Host '  . .\powershell\dsearch.ps1'
    Write-Host '  . .\powershell\dfile.ps1'
    Write-Host "  config dir        $(Get-DnavConfigDir)"
}

Initialize-DnavConfig
