# dnav.ps1 - folder navigation bar for PowerShell (Windows)
# Public commands use function global: so they remain available after load.
#
# Install: Documents\WindowsPowerShell\dnav\
# Load (must dot-source):
#   . "$HOME\Documents\WindowsPowerShell\dnav\dnav.ps1"

function global:Get-DnavInstallDir {
    if ($env:DNAV_HOME -and (Test-Path -LiteralPath $env:DNAV_HOME)) {
        return [System.IO.Path]::GetFullPath($env:DNAV_HOME)
    }
    if ($PSScriptRoot) { return $PSScriptRoot }
    if ($MyInvocation.MyCommand.Path) {
        $here = Split-Path -Parent $MyInvocation.MyCommand.Path
        if ($here) { return $here }
    }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
    return (Join-Path $docs 'WindowsPowerShell\dnav')
}

$global:DnavInstallDir = Get-DnavInstallDir

$__djumpCandidates = @((Join-Path $global:DnavInstallDir 'djump.ps1'))
if ($PSScriptRoot) { $__djumpCandidates += (Join-Path $PSScriptRoot 'djump.ps1') }
if ($MyInvocation.MyCommand.Path) {
    $__djumpCandidates += (Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'djump.ps1')
}
$__djumpLoaded = $false
foreach ($__djumpPath in ($__djumpCandidates | Select-Object -Unique)) {
    if ($__djumpPath -and (Test-Path -LiteralPath $__djumpPath)) {
        . $__djumpPath
        $__djumpLoaded = $true
        break
    }
}
if (-not $__djumpLoaded) {
    Write-Warning "dnav: djump.ps1 not found (looked in $($global:DnavInstallDir)). djump/dfavorite unavailable."
}

function global:Get-DnavConfigDir {
    if ($env:DNAV_CONFIG_DIR) { return $env:DNAV_CONFIG_DIR }
    $install = if ($global:DnavInstallDir) { $global:DnavInstallDir } else { Get-DnavInstallDir }
    return (Join-Path $install 'config')
}

function global:Initialize-DnavConfig {
    $dir = Get-DnavConfigDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $foldersFile = Join-Path $dir 'folders'
    if (-not (Test-Path -LiteralPath $foldersFile)) {
        @"
# Main dnav bar - Label  Path
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

function global:Expand-DnavPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq '-') { return $null }
    if ($Path -eq '~') { return $env:USERPROFILE }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return (Join-Path $env:USERPROFILE $Path.Substring(2))
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function global:Get-DnavFolders {
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
            [pscustomobject]@{ Name = 'Home'; Path = $env:USERPROFILE }
            [pscustomobject]@{ Name = 'Docs'; Path = [Environment]::GetFolderPath('MyDocuments') }
            [pscustomobject]@{ Name = 'Down'; Path = (Join-Path $env:USERPROFILE 'Downloads') }
            [pscustomobject]@{ Name = 'Desktop'; Path = [Environment]::GetFolderPath('Desktop') }
        )
    }
    $list += [pscustomobject]@{ Name = 'About'; Path = $null }
    return $list
}

function global:Get-DnavBrand {
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

function global:Show-DnavSuccessBar {
    param([string]$Path)
    $w = [Math]::Max(20, [Console]::WindowWidth)
    $display = $Path
    if ($display.Length -gt $w) { $display = $display.Substring(0, $w - 1) + [char]0x2026 }
    [Console]::Write("`r")
    Write-Host ($display.PadRight($w)) -ForegroundColor Black -BackgroundColor Cyan
}

function global:Show-DnavAbout {
    Write-Host ''
    Write-Host ' DNav About ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host ''
    Write-Host '  Left/Right or h/l   move | Enter open | Esc leave'
    Write-Host '  dKEY / djump / dfavorite   jump aliases'
    Write-Host "  Install  $global:DnavInstallDir"
    Write-Host "  Config   $(Get-DnavConfigDir)"
    Write-Host ''
}

function global:dnav {
    $items = @(Get-DnavFolders)
    $brand = Get-DnavBrand
    $selected = 0
    $global:__dnavBarWin = 0
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
    } catch { $selected = 0 }

    $cols = [Math]::Max(20, [Console]::WindowWidth)

    function Get-BrandWidth { return ($brand.Length + 3) }

    function Ensure-BarVisible {
        $brandW = Get-BrandWidth
        $avail = [Math]::Max(10, $cols - $brandW)
        $win = $global:__dnavBarWin
        if ($selected -lt $win) { $win = $selected }
        $used = 0
        for ($i = $win; $i -le $selected -and $i -lt $items.Count; $i++) {
            $cell = $items[$i].Name.Length + 3
            if (($used + $cell) -gt $avail -and $i -gt $win) { $win = $selected; break }
            $used += $cell
        }
        if ($win -lt 0) { $win = 0 }
        $used = 0
        for ($i = $win; $i -le $selected -and $i -lt $items.Count; $i++) {
            $cell = $items[$i].Name.Length + 3
            if (($used + $cell) -gt $avail -and $i -eq $selected) {
                $win = $selected
                $used2 = $cell
                while ($win -gt 0) {
                    $prev = $items[$win - 1].Name.Length + 3
                    if (($used2 + $prev) -gt $avail) { break }
                    $used2 += $prev
                    $win--
                }
                break
            }
            $used += $cell
        }
        $global:__dnavBarWin = $win
    }

    function Clear-BarLine {
        $w = [Math]::Max(20, [Console]::WindowWidth)
        [Console]::Write("`r" + (' ' * $w) + "`r")
    }

    function Draw-Bar {
        $cols = [Math]::Max(20, [Console]::WindowWidth)
        Ensure-BarVisible
        $barWin = $global:__dnavBarWin
        $brandW = Get-BrandWidth
        $avail = [Math]::Max(10, $cols - $brandW)
        $moreL = ($barWin -gt 0)
        $used = 0
        $moreR = $false
        $reserveL = if ($moreL) { 2 } else { 0 }
        for ($i = $barWin; $i -lt $items.Count; $i++) {
            $cell = $items[$i].Name.Length + 3
            if ($used -gt 0 -and ($used + $cell) -gt ($avail - $reserveL - 2)) { $moreR = $true; break }
            $used += $cell
        }
        $contentW = $avail
        if ($moreL) { $contentW -= 2 }
        if ($moreR) { $contentW -= 2 }
        if ($contentW -lt 4) { $contentW = 4 }

        [Console]::Write("`r")
        Write-Host (" $brand ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        [Console]::Write(' ')
        if ($moreL) { Write-Host '<' -ForegroundColor DarkGray -NoNewline; [Console]::Write(' ') }
        $used = 0
        for ($i = $barWin; $i -lt $items.Count; $i++) {
            $label = $items[$i].Name
            $cell = $label.Length + 3
            if ($used -gt 0 -and ($used + $cell) -gt $contentW) { $moreR = $true; break }
            if ($i -eq $selected) {
                Write-Host (" $label ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
                [Console]::Write(' ')
            } else {
                [Console]::Write(" $label  ")
            }
            $used += $cell
        }
        if ($moreR) { [Console]::Write(' '); Write-Host '>' -ForegroundColor DarkGray -NoNewline }
        $left = [Console]::CursorLeft
        if ($left -lt $cols) {
            [Console]::Write((' ' * ($cols - $left)))
            [Console]::SetCursorPosition(0, [Console]::CursorTop)
        } else { [Console]::Write("`r") }
    }

    function Navigate-Selected {
        $item = $items[$selected]
        if (-not $item.Path) { Clear-BarLine; Show-DnavAbout; return }
        $path = $item.Path
        if (Test-Path -LiteralPath $path -PathType Container) {
            Set-Location -LiteralPath $path
            Show-DnavSuccessBar ((Get-Location).Path)
        } else {
            Clear-BarLine
            Write-Host "Folder not found: $path" -ForegroundColor Red
        }
    }

    $prevVisible = [Console]::CursorVisible
    try {
        [Console]::CursorVisible = $false
        Draw-Bar
        while ($true) {
            $keyInfo = [Console]::ReadKey($true)
            $key = $keyInfo.Key
            $ch = $keyInfo.KeyChar
            switch ($key) {
                ([ConsoleKey]::LeftArrow)  { if ($selected -gt 0) { $selected--; Draw-Bar } }
                ([ConsoleKey]::RightArrow) { if ($selected -lt ($items.Count - 1)) { $selected++; Draw-Bar } }
                ([ConsoleKey]::Enter)      { Navigate-Selected; return }
                ([ConsoleKey]::Escape)     { Clear-BarLine; return }
                default {
                    if ($ch -eq 'h' -or $ch -eq 'H') { if ($selected -gt 0) { $selected--; Draw-Bar } }
                    elseif ($ch -eq 'l' -or $ch -eq 'L') { if ($selected -lt ($items.Count - 1)) { $selected++; Draw-Bar } }
                    elseif (($ch -eq '/' -or $ch -eq 's' -or $ch -eq 'S') -and $hasSearch) {
                        Clear-BarLine; if (dsearch) { return }; Draw-Bar
                    }
                    elseif (($ch -eq 'f' -or $ch -eq 'F') -and $hasFiles) {
                        Clear-BarLine
                        $fpath = $items[$selected].Path
                        if (-not $fpath -or -not (Test-Path -LiteralPath $fpath -PathType Container)) {
                            $fpath = (Get-Location).Path
                        }
                        if (dfile -StartPath $fpath) { return }
                        Draw-Bar
                    }
                }
            }
        }
    }
    finally { [Console]::CursorVisible = $prevVisible }
}

function global:dhelp {
    Write-Host 'DNav (PowerShell) - core' -ForegroundColor Cyan
    Write-Host '  dnav              open the folder bar'
    Write-Host '  djump / dKEY      jump aliases'
    Write-Host '  dfavorite         manage jumps'
    Write-Host '  dhelp             this text'
    Write-Host "  install           $global:DnavInstallDir"
    Write-Host "  config            $(Get-DnavConfigDir)"
}

Initialize-DnavConfig
