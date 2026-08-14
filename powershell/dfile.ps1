# dfile.ps1 - mini file explorer for DNav (PowerShell, cross-platform)
#
# Layout:
#   row0  DNav Files:  [sibling dirs in parent]
#   row1  [child dirs]
#   row2  ---- Show Hidden o ----
#   row3  [files]
#
# Keys: h/l or arrows  move | j/k or Up/Down  parent/enter
#       Tab or f  toggle dirs/files | .  hidden | Enter  open/exit
#       / or s  search | Esc  cancel
#
# Loaded by dnav.ps1 when present.

if (-not (Get-Command Read-DnavKey -ErrorAction SilentlyContinue)) {
    $__p = $null
    if ($PSScriptRoot) { $__p = Join-Path $PSScriptRoot 'dnav.platform.ps1' }
    if ($__p -and (Test-Path -LiteralPath $__p)) { . $__p }
}

function global:Get-DfileEntries {
    param(
        [string]$Dir,
        [ValidateSet('dirs', 'files')]
        [string]$Kind,
        [bool]$ShowHidden
    )
    $names = [System.Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Dir -PathType Container)) {
        return @()
    }
    try {
        if ($Kind -eq 'dirs') {
            foreach ($d in [System.IO.Directory]::EnumerateDirectories($Dir)) {
                $name = [System.IO.Path]::GetFileName($d)
                if ($name -eq '.' -or $name -eq '..') { continue }
                if (-not $ShowHidden -and $name.StartsWith('.')) { continue }
                if (-not $ShowHidden) {
                    try {
                        $attr = [System.IO.File]::GetAttributes($d)
                        if (($attr -band [System.IO.FileAttributes]::Hidden) -ne 0) { continue }
                    } catch { }
                }
                $names.Add($name) | Out-Null
            }
        } else {
            foreach ($f in [System.IO.Directory]::EnumerateFiles($Dir)) {
                $name = [System.IO.Path]::GetFileName($f)
                if (-not $ShowHidden -and $name.StartsWith('.')) { continue }
                if (-not $ShowHidden) {
                    try {
                        $attr = [System.IO.File]::GetAttributes($f)
                        if (($attr -band [System.IO.FileAttributes]::Hidden) -ne 0) { continue }
                    } catch { }
                }
                $names.Add($name) | Out-Null
            }
        }
    } catch {
        return @()
    }
    return @($names | Sort-Object)
}

function global:Get-DfileWindow {
    param(
        [string[]]$Items,
        [int]$Sel,
        [int]$Win,
        [int]$MaxWidth
    )
    $n = $Items.Count
    if ($n -eq 0) {
        return @{ Vis = @(); Win = 0 }
    }
    if ($Sel -lt 0) { $Sel = 0 }
    if ($Sel -ge $n) { $Sel = $n - 1 }
    if ($Win -lt 0) { $Win = 0 }
    if ($Win -gt $Sel) { $Win = $Sel }

    $guard = 0
    while ($guard -lt 40) {
        $guard++
        $vis = [System.Collections.Generic.List[string]]::new()
        $used = 0
        for ($i = $Win; $i -lt $n; $i++) {
            $label = $Items[$i]
            $w = $label.Length + 3
            if ($vis.Count -gt 0 -and ($used + $w) -gt $MaxWidth) { break }
            if ($vis.Count -eq 0 -and $w -gt $MaxWidth) {
                $vis.Add($label) | Out-Null
                break
            }
            $vis.Add($label) | Out-Null
            $used += $w
        }
        $vcount = $vis.Count
        if ($vcount -eq 0) { break }
        $selSlot = $Sel - $Win
        if ($selSlot -ge $vcount) {
            if ($vcount -ge 2) { $Win = $Sel - ($vcount - 2) } else { $Win = $Sel }
            if ($Win -lt 0) { $Win = 0 }
            continue
        }
        if ($selSlot -eq ($vcount - 1) -and $Sel -lt ($n - 1) -and $vcount -ge 2) {
            $nwin = $Sel - ($vcount - 2)
            if ($nwin -lt 0) { $nwin = 0 }
            if ($nwin -ne $Win) { $Win = $nwin; continue }
        }
        break
    }
    return @{ Vis = @($vis); Win = $Win }
}

function global:Write-DfileStrip {
    param(
        [string[]]$Items,
        [int]$Sel,
        [int]$Win,
        [bool]$Active,
        [int]$MaxWidth,
        [int]$Row,
        [int]$StartCol = 0
    )
    $n = $Items.Count
    $contentW = $MaxWidth
    $winInfo = Get-DfileWindow -Items $Items -Sel $Sel -Win $Win -MaxWidth $contentW
    $Win = $winInfo.Win
    $moreL = ($Win -gt 0)
    $moreR = ($n -gt 0 -and ($Win + $winInfo.Vis.Count) -lt $n)

    $indL = if ($moreL) { 2 } else { 0 }
    $indR = if ($moreR) { 2 } else { 0 }
    if (($indL + $indR) -gt 0) {
        $contentW = $MaxWidth - $indL - $indR
        if ($contentW -lt 4) { $contentW = 4 }
        $winInfo = Get-DfileWindow -Items $Items -Sel $Sel -Win $Win -MaxWidth $contentW
        $Win = $winInfo.Win
        $moreL = ($Win -gt 0)
        $moreR = ($n -gt 0 -and ($Win + $winInfo.Vis.Count) -lt $n)
    }

    [Console]::SetCursorPosition($StartCol, $Row)
    $col = $StartCol
    if ($moreL) {
        Write-Host '<' -ForegroundColor DarkGray -NoNewline
        $col++
        Write-Host ' ' -NoNewline
        $col++
    }

    $used = 0
    for ($i = $Win; $i -lt $n; $i++) {
        $label = $Items[$i]
        $cellW = $label.Length + 3
        if ($used -gt 0 -and ($used + $cellW) -gt $contentW) { break }
        if ($used -eq 0 -and $cellW -gt $contentW) {
            $take = [Math]::Max(1, $contentW - 2)
            $label = $label.Substring(0, [Math]::Min($label.Length, $take)) + [char]0x2026
            $cellW = $contentW
        }
        if ($Active -and $i -eq $Sel) {
            Write-Host (" $label ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        } else {
            Write-Host (" $label ") -NoNewline
        }
        $used += $cellW
        $col += $cellW
    }
    if ($moreR) {
        Write-Host ' >' -ForegroundColor DarkGray -NoNewline
        $col += 2
    }
    $clear = [Console]::WindowWidth - $col
    if ($clear -gt 0) { [Console]::Write((' ' * $clear)) }

    return $Win
}

function global:dfile {
    param(
        [string]$StartPath = ''
    )
    if (-not (Get-Command Read-DnavKey -ErrorAction SilentlyContinue)) {
        function script:Read-DnavKey {
            $ki = [Console]::ReadKey($true)
            return [pscustomobject]@{ Key = $ki.Key; Char = $ki.KeyChar; Ctrl = $false }
        }
    }

    if ($StartPath -and (Test-Path -LiteralPath $StartPath -PathType Container)) {
        Set-Location -LiteralPath $StartPath
    }

    # Hashtable state — nested functions share the same object by reference.
    # (Bare $siblings = ... / $script:siblings = ... do NOT update each other.)
    $st = @{
        ShowHidden = $false
        Focus      = 'children'
        SelS = 0; SelC = 0; SelF = 0
        WinS = 0; WinC = 0; WinF = 0
        Siblings = @(); Children = @(); Files = @()
        Cwd = ''; Parent = ''; PermDenied = ''
        StartRow = 0
    }

    for ($i = 0; $i -lt 4; $i++) { [Console]::WriteLine() }
    $st.StartRow = [Console]::CursorTop - 4

    function Clear-DfileArea {
        $winW = if (Get-Command Get-DnavConsoleWidth -ErrorAction SilentlyContinue) {
            Get-DnavConsoleWidth
        } else {
            [Math]::Max(20, [Console]::WindowWidth)
        }
        for ($r = 0; $r -lt 4; $r++) {
            try {
                [Console]::SetCursorPosition(0, $st.StartRow + $r)
                [Console]::Write((' ' * $winW))
            } catch { }
        }
    }

    function Refresh-Dfile {
        try {
            $st.Cwd = [System.IO.Path]::GetFullPath((Get-Location).Path)
        } catch {
            $st.Cwd = (Get-Location).Path
        }
        $st.Parent = [System.IO.Path]::GetDirectoryName($st.Cwd)
        if ([string]::IsNullOrEmpty($st.Parent)) {
            $st.Parent = $st.Cwd
        }
        $st.PermDenied = ''
        $st.Siblings = @(Get-DfileEntries -Dir $st.Parent -Kind dirs -ShowHidden $st.ShowHidden)
        $st.Children = @(Get-DfileEntries -Dir $st.Cwd -Kind dirs -ShowHidden $st.ShowHidden)
        $st.Files = @(Get-DfileEntries -Dir $st.Cwd -Kind files -ShowHidden $st.ShowHidden)

        $base = [System.IO.Path]::GetFileName($st.Cwd.TrimEnd('\', '/'))
        if (-not $base) { $base = $st.Cwd }
        $st.SelS = 0
        for ($i = 0; $i -lt $st.Siblings.Count; $i++) {
            if ($st.Siblings[$i] -eq $base) { $st.SelS = $i; break }
        }
        if ($st.Children.Count -eq 0) { $st.SelC = 0 }
        elseif ($st.SelC -ge $st.Children.Count) { $st.SelC = $st.Children.Count - 1 }
        if ($st.Files.Count -eq 0) { $st.SelF = 0 }
        elseif ($st.SelF -ge $st.Files.Count) { $st.SelF = $st.Files.Count - 1 }

        if ($st.Focus -eq 'children' -and $st.Children.Count -eq 0 -and $st.Files.Count -gt 0) {
            $st.Focus = 'files'
        } elseif ($st.Focus -eq 'files' -and $st.Files.Count -eq 0 -and $st.Children.Count -gt 0) {
            $st.Focus = 'children'
        }
    }

    function Draw-Dfile {
        $winW = if (Get-Command Get-DnavConsoleWidth -ErrorAction SilentlyContinue) {
            Get-DnavConsoleWidth
        } else {
            [Math]::Max(20, [Console]::WindowWidth)
        }
        Clear-DfileArea

        try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
        # Chip ends at colon; space after chip is normal (matches zsh/bash)
        $brand = ' DNav Files:'
        Write-Host $brand -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        try { [Console]::Write(' ') } catch { Write-Host ' ' -NoNewline }
        $restW = $winW - $brand.Length - 1
        if ($restW -lt 8) { $restW = 8 }
        # Parent strip is display-only (cwd highlighted)
        $st.WinS = Write-DfileStrip -Items $st.Siblings -Sel $st.SelS -Win $st.WinS -Active $true `
            -MaxWidth $restW -Row $st.StartRow -StartCol $brand.Length

        $activeC = ($st.Focus -eq 'children')
        $st.WinC = Write-DfileStrip -Items $st.Children -Sel $st.SelC -Win $st.WinC -Active $activeC `
            -MaxWidth $winW -Row ($st.StartRow + 1) -StartCol 0

        try { [Console]::SetCursorPosition(0, $st.StartRow + 2) } catch { }
        $hid = if ($st.ShowHidden) { [char]0x25CF } else { [char]0x25CB }
        $left = "- Show Hidden $hid "
        $fc = $st.Files.Count
        $dc = $st.Children.Count
        $mid = " dirs:$dc files:$fc "
        $right = if ($st.PermDenied) { " Denied: $($st.PermDenied) " } else { $mid }
        if (($left.Length + $right.Length) -gt $winW -and $right) {
            $room = [Math]::Max(8, $winW - $left.Length - 5)
            $right = ' ...' + $right.Substring([Math]::Max(0, $right.Length - $room))
        }
        $fill = $winW - $left.Length - $right.Length
        if ($fill -lt 0) { $fill = 0 }
        Write-Host $left -NoNewline
        Write-Host (('-' * $fill)) -NoNewline
        if ($right) { Write-Host $right -ForegroundColor DarkGray -NoNewline }

        $activeF = ($st.Focus -eq 'files')
        $st.WinF = Write-DfileStrip -Items $st.Files -Sel $st.SelF -Win $st.WinF -Active $activeF `
            -MaxWidth $winW -Row ($st.StartRow + 3) -StartCol 0

        try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
    }

    function Go-DfileDir([string]$Dest) {
        if (-not (Test-Path -LiteralPath $Dest -PathType Container)) { return $false }
        try {
            Set-Location -LiteralPath $Dest
        } catch {
            $st.PermDenied = $Dest
            Draw-Dfile
            return $false
        }
        $st.WinC = 0; $st.WinF = 0
        $st.SelC = 0; $st.SelF = 0
        Refresh-Dfile
        Draw-Dfile
        return $true
    }

    function Move-DfileH([int]$Dir) {
        if ($st.Focus -eq 'children') {
            if ($st.Children.Count -eq 0) { return }
            $st.SelC += $Dir
            if ($st.SelC -lt 0) { $st.SelC = 0 }
            if ($st.SelC -ge $st.Children.Count) { $st.SelC = $st.Children.Count - 1 }
        } else {
            if ($st.Files.Count -eq 0) { return }
            $st.SelF += $Dir
            if ($st.SelF -lt 0) { $st.SelF = 0 }
            if ($st.SelF -ge $st.Files.Count) { $st.SelF = $st.Files.Count - 1 }
        }
        Draw-Dfile
    }

    function Toggle-DfileFocus {
        $prev = $st.Focus
        if ($st.Focus -eq 'files') { $st.Focus = 'children' } else { $st.Focus = 'files' }
        if ($st.Focus -eq 'children' -and $st.Children.Count -eq 0 -and $st.Files.Count -gt 0) {
            $st.Focus = 'files'
        } elseif ($st.Focus -eq 'files' -and $st.Files.Count -eq 0 -and $st.Children.Count -gt 0) {
            $st.Focus = 'children'
        }
        if ($st.Focus -ne $prev) { Draw-Dfile }
    }

    function Exit-ToSelectedDir {
        if ($st.Focus -ne 'children' -or $st.Children.Count -eq 0) { return $false }
        $dest = Join-Path $st.Cwd $st.Children[$st.SelC]
        Clear-DfileArea
        try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
        if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
            Write-Host "Folder not found: $dest" -ForegroundColor Red
            return $true
        }
        Set-Location -LiteralPath $dest
        $full = (Get-Location).Path
        if (Get-Command Show-DnavSuccessBar -ErrorAction SilentlyContinue) {
            Show-DnavSuccessBar $full
        } else {
            Write-Host $full -ForegroundColor Black -BackgroundColor Cyan
        }
        return $true
    }

    function Open-SelectedFile {
        if ($st.Focus -ne 'files' -or $st.Files.Count -eq 0) { return $false }
        $fpath = Join-Path $st.Cwd $st.Files[$st.SelF]
        Clear-DfileArea
        try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
        if (-not (Test-Path -LiteralPath $fpath)) {
            Write-Host "File not found: $fpath" -ForegroundColor Red
            return $true
        }
        if (Get-Command Show-DnavSuccessBar -ErrorAction SilentlyContinue) {
            Show-DnavSuccessBar $fpath
        } else {
            Write-Host $fpath -ForegroundColor Black -BackgroundColor Cyan
        }
        if ($env:EDITOR) {
            & $env:EDITOR $fpath
        } elseif (Get-Command xdg-open -ErrorAction SilentlyContinue) {
            Start-Process -FilePath 'xdg-open' -ArgumentList $fpath -ErrorAction SilentlyContinue
        } else {
            try {
                Start-Process -FilePath $fpath -ErrorAction Stop
            } catch {
                Write-Host "Could not open: $fpath" -ForegroundColor Red
            }
        }
        return $true
    }

    $prevVis = $true
    try {
        try { $prevVis = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch { }
        Refresh-Dfile
        Draw-Dfile

        while ($true) {
            $k = Read-DnavKey
            $key = $k.Key
            $ch = $k.Char

            if ($key -eq [ConsoleKey]::LeftArrow -or $ch -eq 'h' -or $ch -eq 'H') {
                Move-DfileH -1; continue
            }
            if ($key -eq [ConsoleKey]::RightArrow -or $ch -eq 'l' -or $ch -eq 'L') {
                Move-DfileH 1; continue
            }
            if ($key -eq [ConsoleKey]::UpArrow -or $ch -eq 'k' -or $ch -eq 'K') {
                $root = [System.IO.Path]::GetPathRoot($st.Cwd)
                if ($st.Cwd -ne $root -and $st.Parent -and $st.Parent -ne $st.Cwd) {
                    [void](Go-DfileDir $st.Parent)
                }
                continue
            }
            if ($key -eq [ConsoleKey]::DownArrow -or $ch -eq 'j' -or $ch -eq 'J') {
                if ($st.Focus -eq 'children' -and $st.Children.Count -gt 0) {
                    $dest = Join-Path $st.Cwd $st.Children[$st.SelC]
                    [void](Go-DfileDir $dest)
                }
                continue
            }
            if ($key -eq [ConsoleKey]::Tab -or $ch -eq 'f' -or $ch -eq 'F') {
                Toggle-DfileFocus; continue
            }
            if ($key -eq [ConsoleKey]::Enter) {
                if ($st.Focus -eq 'files') {
                    if (Open-SelectedFile) { return $true }
                } else {
                    if (Exit-ToSelectedDir) { return $true }
                }
                continue
            }
            if ($key -eq [ConsoleKey]::Escape) {
                Clear-DfileArea
                try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
                return $false
            }
            if ($ch -eq '.') {
                $st.ShowHidden = -not $st.ShowHidden
                Refresh-Dfile
                Draw-Dfile
                continue
            }
            if ($ch -eq '/' -or $ch -eq 's' -or $ch -eq 'S') {
                if (Get-Command dsearch -ErrorAction SilentlyContinue) {
                    Clear-DfileArea
                    try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
                    $nav = dsearch
                    if ($nav) { return $true }
                    for ($i = 0; $i -lt 4; $i++) { [Console]::WriteLine() }
                    $st.StartRow = [Console]::CursorTop - 4
                    Refresh-Dfile
                    Draw-Dfile
                }
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $prevVis } catch { }
    }
}
