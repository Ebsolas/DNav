# dnav.ps1 - folder navigation bar for PowerShell (Windows + Linux/macOS pwsh)
# Public commands use function global: so they remain available after load.
#
# Load (must dot-source):
#   Windows:  . "$HOME\Documents\PowerShell\dnav\dnav.ps1"
#   Linux:    . "$HOME/.local/share/dnav-ps/dnav.ps1"
#   Or:       $env:DNAV_HOME = '...'; . "$env:DNAV_HOME/dnav.ps1"
#
# Optional: set DNAV_CONFIG_DIR (default: XDG ~/.config/dnav on Unix,
# install\config on Windows).

# ── Platform helpers ─────────────────────────────────────────────────────
$__plat = $null
if ($PSScriptRoot) {
    $__plat = Join-Path $PSScriptRoot 'dnav.platform.ps1'
} elseif ($MyInvocation.MyCommand.Path) {
    $__plat = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) 'dnav.platform.ps1'
}
if ($__plat -and (Test-Path -LiteralPath $__plat)) {
    . $__plat
} else {
    Write-Warning "dnav: dnav.platform.ps1 missing; path helpers may be limited."
}

function global:Get-DnavInstallDir {
    return (Get-DnavDefaultInstallDir)
}

$global:DnavInstallDir = Get-DnavInstallDir

function global:Get-DnavConfigDir {
    return (Get-DnavDefaultConfigDir)
}

# ── Load sibling modules (must be top-level . so functions stay global) ──
# NOTE: do not wrap this in a function — `. file` inside a function scopes
# bare `function foo` to that function and they vanish on return.
$__dnavSiblingNames = @('djump.ps1', 'dsearch.ps1', 'dfile.ps1')
foreach ($__sibName in $__dnavSiblingNames) {
    $__sibCandidates = @()
    if ($global:DnavInstallDir) {
        $__sibCandidates += (Join-Path $global:DnavInstallDir $__sibName)
    }
    if ($PSScriptRoot) {
        $__sibCandidates += (Join-Path $PSScriptRoot $__sibName)
    }
    $__loaded = $false
    foreach ($__sibPath in ($__sibCandidates | Select-Object -Unique)) {
        if ($__sibPath -and (Test-Path -LiteralPath $__sibPath)) {
            . $__sibPath
            $__loaded = $true
            break
        }
    }
    if (-not $__loaded -and $__sibName -eq 'djump.ps1') {
        Write-Warning "dnav: djump.ps1 not found (looked under $($global:DnavInstallDir))"
    }
}
Remove-Variable __dnavSiblingNames, __sibName, __sibCandidates, __sibPath, __loaded -ErrorAction SilentlyContinue

function global:Initialize-DnavConfig {
    $dir = Get-DnavConfigDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $foldersFile = Join-Path $dir 'folders'
    if (-not (Test-Path -LiteralPath $foldersFile)) {
        if (Test-DnavWindows) {
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
        } else {
            @"
# Main dnav bar - Label  Path
Home        ~
Docs        ~/Documents
Down        ~/Downloads
Projects    ~/Projects
Config      ~/.config
Share       ~/.local/share
Apps        ~/Apps
"@ | Set-Content -LiteralPath $foldersFile -Encoding UTF8
        }
    }
    $configFile = Join-Path $dir 'config'
    if (-not (Test-Path -LiteralPath $configFile)) {
        @"
# DNav settings
brand = DNav
ls_after = 0
success_anim = 1
success_anim_steps = 8
success_anim_ms = 25
"@ | Set-Content -LiteralPath $configFile -Encoding UTF8
    }
}

function global:Expand-DnavPath {
    param([string]$Path)
    return (Expand-DnavUserPath $Path)
}

function global:Get-DnavSettings {
    # Shared ~/.config/dnav/config (same keys as zsh/bash)
    $s = @{
        Brand             = 'DNav'
        LsAfter           = $false
        SuccessAnim       = $true
        SuccessAnimSteps  = 8
        SuccessAnimMs     = 25
    }
    Initialize-DnavConfig
    $configFile = Join-Path (Get-DnavConfigDir) 'config'
    if (-not (Test-Path -LiteralPath $configFile)) { return $s }

    Get-Content -LiteralPath $configFile -ErrorAction SilentlyContinue | ForEach-Object {
        $line = ($_ -split '#')[0].Trim()
        if (-not $line -or $line -notmatch '=') { return }
        $key = ($line.Split('=', 2)[0]).Trim().ToLowerInvariant()
        $val = ($line.Split('=', 2)[1]).Trim().Trim('"', "'")
        switch ($key) {
            'brand' {
                if ($val) { $s.Brand = $val }
            }
            { $_ -in @('ls_after', 'ls') } {
                $s.LsAfter = ($val -match '^(1|true|yes|on)$')
            }
            { $_ -in @('success_anim', 'anim') } {
                $s.SuccessAnim = ($val -match '^(1|true|yes|on)$')
            }
            'success_anim_steps' {
                if ($val -match '^\d+$') { $s.SuccessAnimSteps = [int]$val }
            }
            'success_anim_ms' {
                if ($val -match '^\d+$') { $s.SuccessAnimMs = [int]$val }
            }
        }
    }

    # Env overrides (optional)
    if ($env:DNAV_SUCCESS_ANIM_STEPS -match '^\d+$') {
        $s.SuccessAnimSteps = [int]$env:DNAV_SUCCESS_ANIM_STEPS
    }
    if ($env:DNAV_SUCCESS_ANIM_MS -match '^\d+$') {
        $s.SuccessAnimMs = [int]$env:DNAV_SUCCESS_ANIM_MS
    }
    return $s
}

function global:Get-DnavFolders {
    Initialize-DnavConfig
    $foldersFile = Join-Path (Get-DnavConfigDir) 'folders'
    $list = @()
    $userHome = Get-DnavUserHome
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
        $docs = $null
        try { $docs = [Environment]::GetFolderPath('MyDocuments') } catch { }
        if (-not $docs) { $docs = Join-Path $userHome 'Documents' }
        $list = @(
            [pscustomobject]@{ Name = 'Home'; Path = $userHome }
            [pscustomobject]@{ Name = 'Docs'; Path = $docs }
            [pscustomobject]@{ Name = 'Down'; Path = (Join-Path $userHome 'Downloads') }
        )
        if (Test-DnavWindows) {
            try {
                $desk = [Environment]::GetFolderPath('Desktop')
                if ($desk) { $list += [pscustomobject]@{ Name = 'Desktop'; Path = $desk } }
            } catch { }
        } else {
            $proj = Join-Path $userHome 'Projects'
            if (Test-Path -LiteralPath $proj) {
                $list += [pscustomobject]@{ Name = 'Projects'; Path = $proj }
            }
        }
    }
    $list += [pscustomobject]@{ Name = 'About'; Path = $null }
    return $list
}

function global:Get-DnavBrand {
    return (Get-DnavSettings).Brand
}

function global:Show-DnavSuccessBar {
    param(
        [string]$Path,
        [int]$OriginMid = -1
    )
    $cfg = Get-DnavSettings
    $w = Get-DnavConsoleWidth
    if ($OriginMid -lt 0) { $OriginMid = [int]($w / 2) }
    $display = $Path
    if ($display.Length -gt $w) { $display = $display.Substring(0, $w - 1) + [char]0x2026 }

    $esc = [char]27
    $hl = "${esc}[30;46m"
    $rst = "${esc}[0m"
    $prevVis = $true
    try {
        try { $prevVis = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch { }

        if ($cfg.SuccessAnim) {
            $steps = [int]$cfg.SuccessAnimSteps
            $ms = [int]$cfg.SuccessAnimMs
            if ($steps -lt 1) { $steps = 1 }
            if ($ms -lt 1) { $ms = 1 }
            for ($step = 1; $step -le $steps; $step++) {
                $half = [int](($w * $step) / (2 * $steps))
                $left = $OriginMid - $half
                $right = $OriginMid + $half
                if ($left -lt 0) { $left = 0 }
                if ($right -gt $w) { $right = $w }
                $width = $right - $left
                if ($width -lt 0) { $width = 0 }
                $frame = (' ' * $left) + $hl + (' ' * $width) + $rst
                [Console]::Write("`r${esc}[2K$frame")
                Start-Sleep -Milliseconds $ms
            }
        }

        $final = $display
        if ($final.Length -lt $w) { $final = $final.PadRight($w) }
        elseif ($final.Length -gt $w) { $final = $final.Substring(0, $w) }
        [Console]::Write("`r${esc}[2K$hl$final$rst`n")
    } finally {
        try { [Console]::CursorVisible = $prevVis } catch { }
    }
}

function global:Show-DnavAbout {
    Write-Host ''
    Write-Host ' DNav About ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host ''
    Write-Host '  Left/Right or h/l   move | Enter open | Esc leave'
    Write-Host '  / or s              search (if dsearch loaded)'
    Write-Host '  f                   file explorer (if dfile loaded)'
    Write-Host '  dKEY / djump / dfavorite   jump aliases'
    Write-Host "  Install  $global:DnavInstallDir"
    Write-Host "  Config   $(Get-DnavConfigDir)"
    $plat = if (Test-DnavWindows) { 'Windows' } else { 'Unix' }
    Write-Host "  Host     PowerShell $($PSVersionTable.PSVersion) on $plat"
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

    $cols = Get-DnavConsoleWidth

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
        $w = Get-DnavConsoleWidth
        try { [Console]::Write("`r" + (' ' * $w) + "`r") } catch { Write-Host '' }
    }

    function Draw-Bar {
        $cols = Get-DnavConsoleWidth
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

        try { [Console]::Write("`r") } catch { }
        # Brand chip: " DNav " (spaces inside); one normal space after chip before items
        Write-Host (" $brand ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        try { [Console]::Write(' ') } catch { Write-Host ' ' -NoNewline }
        if ($moreL) { Write-Host '<' -ForegroundColor DarkGray -NoNewline; try { [Console]::Write(' ') } catch { } }
        $used = 0
        for ($i = $barWin; $i -lt $items.Count; $i++) {
            $label = $items[$i].Name
            $cell = $label.Length + 3
            if ($used -gt 0 -and ($used + $cell) -gt $contentW) { $moreR = $true; break }
            if ($i -eq $selected) {
                Write-Host (" $label ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
                try { [Console]::Write(' ') } catch { }
            } else {
                try { [Console]::Write(" $label  ") } catch { Write-Host " $label  " -NoNewline }
            }
            $used += $cell
        }
        if ($moreR) {
            try { [Console]::Write(' ') } catch { }
            Write-Host '>' -ForegroundColor DarkGray -NoNewline
        }
        try {
            $left = [Console]::CursorLeft
            if ($left -lt $cols) {
                [Console]::Write((' ' * ($cols - $left)))
                [Console]::SetCursorPosition(0, [Console]::CursorTop)
            } else { [Console]::Write("`r") }
        } catch { }
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

    Invoke-DnavWithHiddenCursor {
        Draw-Bar
        while ($true) {
            $k = Read-DnavKey
            switch ($k.Key) {
                ([ConsoleKey]::LeftArrow)  { if ($selected -gt 0) { $selected--; Draw-Bar } }
                ([ConsoleKey]::RightArrow) { if ($selected -lt ($items.Count - 1)) { $selected++; Draw-Bar } }
                ([ConsoleKey]::Enter)      { Navigate-Selected; return }
                ([ConsoleKey]::Escape)     { Clear-BarLine; return }
                default {
                    $ch = $k.Char
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
}

function global:dhelp {
    Write-Host 'DNav (PowerShell) - cross-platform' -ForegroundColor Cyan
    Write-Host '  dnav              open the folder bar'
    Write-Host '  dsearch           fuzzy directory search'
    Write-Host '  dfile             mini file explorer'
    Write-Host '  djump / dKEY      jump aliases'
    Write-Host '  dfavorite         manage jumps'
    Write-Host '  dhelp             this text'
    Write-Host "  install           $global:DnavInstallDir"
    Write-Host "  config            $(Get-DnavConfigDir)"
    $mods = @()
    if (Get-Command dsearch -ErrorAction SilentlyContinue) { $mods += 'dsearch' }
    if (Get-Command dfile -ErrorAction SilentlyContinue) { $mods += 'dfile' }
    if (Get-Command djump -ErrorAction SilentlyContinue) { $mods += 'djump' }
    Write-Host "  loaded            $($mods -join ', ')"
}

Initialize-DnavConfig
