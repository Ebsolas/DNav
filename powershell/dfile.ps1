# dfile.ps1 - mini file explorer for DNav (PowerShell / Windows)
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
# Dot-source with the other modules:
#   . .\powershell\dnav.ps1
#   . .\powershell\dfile.ps1

function Ensure-ConsoleInputType {
    if (-not ([System.Management.Automation.PSTypeName]'ConsoleInput').Type) {
        Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class ConsoleInput {
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr GetStdHandle(int nStdHandle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool ReadConsoleInput(IntPtr hConsoleInput, ref INPUT_RECORD lpBuffer, uint nLength, out uint lpNumberOfEventsRead);
    public const int STD_INPUT_HANDLE = -10;
    public const uint ENABLE_QUICK_EDIT_MODE = 0x0040;
    public const uint ENABLE_EXTENDED_FLAGS = 0x0080;
    [StructLayout(LayoutKind.Sequential)]
    public struct COORD { public short X; public short Y; }
    [StructLayout(LayoutKind.Explicit, CharSet = CharSet.Unicode)]
    public struct KEY_EVENT_RECORD {
        [FieldOffset(0)] public bool bKeyDown;
        [FieldOffset(4)] public short wRepeatCount;
        [FieldOffset(6)] public short wVirtualKeyCode;
        [FieldOffset(8)] public short wVirtualScanCode;
        [FieldOffset(10)] public char UnicodeChar;
        [FieldOffset(12)] public int dwControlKeyState;
    }
    [StructLayout(LayoutKind.Explicit)]
    public struct INPUT_RECORD {
        [FieldOffset(0)] public short EventType;
        [FieldOffset(4)] public KEY_EVENT_RECORD KeyEvent;
    }
}
"@
    }
}

function Get-DfileEntries {
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

function Get-DfileWindow {
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

function Write-DfileStrip {
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

function dfile {
    param(
        [string]$StartPath = ''
    )
    Ensure-ConsoleInputType

    if ($StartPath -and (Test-Path -LiteralPath $StartPath -PathType Container)) {
        Set-Location -LiteralPath $StartPath
    }

    $showHidden = $false
    $focus = 'children'
    $selS = 0; $selC = 0; $selF = 0
    $winS = 0; $winC = 0; $winF = 0
    $siblings = @(); $children = @(); $files = @()
    $cwd = ''; $parent = ''; $permDenied = ''

    $handle = [ConsoleInput]::GetStdHandle([ConsoleInput]::STD_INPUT_HANDLE)
    $mode = 0
    [ConsoleInput]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    $newMode = ($mode -band (-bnot [ConsoleInput]::ENABLE_QUICK_EDIT_MODE)) -bor [ConsoleInput]::ENABLE_EXTENDED_FLAGS
    [ConsoleInput]::SetConsoleMode($handle, $newMode) | Out-Null

    for ($i = 0; $i -lt 4; $i++) { [Console]::WriteLine() }
    $startRow = [Console]::CursorTop - 4

    $record = New-Object ConsoleInput+INPUT_RECORD
    $eventsRead = 0

    function Clear-DfileArea {
        $winW = [Console]::WindowWidth
        for ($r = 0; $r -lt 4; $r++) {
            [Console]::SetCursorPosition(0, $startRow + $r)
            [Console]::Write((' ' * $winW))
        }
    }

    function Refresh-Dfile {
        try {
            $script:cwd = [System.IO.Path]::GetFullPath((Get-Location).Path)
        } catch {
            $script:cwd = (Get-Location).Path
        }
        $script:parent = [System.IO.Path]::GetDirectoryName($script:cwd)
        if ([string]::IsNullOrEmpty($script:parent)) {
            $script:parent = $script:cwd
        }
        $script:permDenied = ''
        $script:siblings = @(Get-DfileEntries -Dir $script:parent -Kind dirs -ShowHidden $showHidden)
        $script:children = @(Get-DfileEntries -Dir $script:cwd -Kind dirs -ShowHidden $showHidden)
        $script:files = @(Get-DfileEntries -Dir $script:cwd -Kind files -ShowHidden $showHidden)

        $base = [System.IO.Path]::GetFileName($script:cwd.TrimEnd('\', '/'))
        if (-not $base) { $base = $script:cwd }
        $script:selS = 0
        for ($i = 0; $i -lt $script:siblings.Count; $i++) {
            if ($script:siblings[$i] -eq $base) { $script:selS = $i; break }
        }
        if ($script:children.Count -eq 0) { $script:selC = 0 }
        elseif ($script:selC -ge $script:children.Count) { $script:selC = $script:children.Count - 1 }
        if ($script:files.Count -eq 0) { $script:selF = 0 }
        elseif ($script:selF -ge $script:files.Count) { $script:selF = $script:files.Count - 1 }

        if ($script:focus -eq 'children' -and $script:children.Count -eq 0 -and $script:files.Count -gt 0) {
            $script:focus = 'files'
        } elseif ($script:focus -eq 'files' -and $script:files.Count -eq 0 -and $script:children.Count -gt 0) {
            $script:focus = 'children'
        }
    }

    function Draw-Dfile {
        $winW = [Console]::WindowWidth
        Clear-DfileArea

        [Console]::SetCursorPosition(0, $startRow)
        $brand = ' DNav Files: '
        Write-Host $brand -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        $restW = $winW - $brand.Length
        if ($restW -lt 8) { $restW = 8 }
        $script:winS = Write-DfileStrip -Items $siblings -Sel $selS -Win $winS -Active $true `
            -MaxWidth $restW -Row $startRow -StartCol $brand.Length

        $activeC = ($focus -eq 'children')
        $script:winC = Write-DfileStrip -Items $children -Sel $selC -Win $winC -Active $activeC `
            -MaxWidth $winW -Row ($startRow + 1) -StartCol 0

        [Console]::SetCursorPosition(0, $startRow + 2)
        $hid = if ($showHidden) { [char]0x25CF } else { [char]0x25CB }
        $left = "- Show Hidden $hid "
        $right = if ($permDenied) { " Permission Denied: $permDenied " } else { '' }
        if (($left.Length + $right.Length) -gt $winW -and $right) {
            $room = [Math]::Max(8, $winW - $left.Length - 5)
            $right = ' ...' + $right.Substring([Math]::Max(0, $right.Length - $room))
        }
        $fill = $winW - $left.Length - $right.Length
        if ($fill -lt 0) { $fill = 0 }
        Write-Host $left -NoNewline
        Write-Host (('-' * $fill)) -NoNewline
        if ($right) { Write-Host $right -ForegroundColor DarkYellow -NoNewline }

        $activeF = ($focus -eq 'files')
        $script:winF = Write-DfileStrip -Items $files -Sel $selF -Win $winF -Active $activeF `
            -MaxWidth $winW -Row ($startRow + 3) -StartCol 0

        [Console]::SetCursorPosition(0, $startRow)
    }

    function Go-DfileDir([string]$Dest) {
        if (-not (Test-Path -LiteralPath $Dest -PathType Container)) { return $false }
        try {
            Set-Location -LiteralPath $Dest
        } catch {
            $script:permDenied = $Dest
            Draw-Dfile
            return $false
        }
        $script:winC = 0; $script:winF = 0
        $script:selC = 0; $script:selF = 0
        Refresh-Dfile
        Draw-Dfile
        return $true
    }

    function Move-DfileH([int]$Dir) {
        if ($focus -eq 'children') {
            if ($children.Count -eq 0) { return }
            $script:selC += $Dir
            if ($script:selC -lt 0) { $script:selC = 0 }
            if ($script:selC -ge $children.Count) { $script:selC = $children.Count - 1 }
        } else {
            if ($files.Count -eq 0) { return }
            $script:selF += $Dir
            if ($script:selF -lt 0) { $script:selF = 0 }
            if ($script:selF -ge $files.Count) { $script:selF = $files.Count - 1 }
        }
        Draw-Dfile
    }

    function Toggle-DfileFocus {
        $prev = $focus
        if ($focus -eq 'files') { $script:focus = 'children' } else { $script:focus = 'files' }
        if ($script:focus -eq 'children' -and $children.Count -eq 0 -and $files.Count -gt 0) {
            $script:focus = 'files'
        } elseif ($script:focus -eq 'files' -and $files.Count -eq 0 -and $children.Count -gt 0) {
            $script:focus = 'children'
        }
        if ($script:focus -ne $prev) { Draw-Dfile }
    }

    function Exit-ToSelectedDir {
        if ($focus -ne 'children' -or $children.Count -eq 0) { return $false }
        $dest = Join-Path $cwd $children[$selC]
        Clear-DfileArea
        [Console]::SetCursorPosition(0, $startRow)
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
        if ($focus -ne 'files' -or $files.Count -eq 0) { return $false }
        $fpath = Join-Path $cwd $files[$selF]
        Clear-DfileArea
        [Console]::SetCursorPosition(0, $startRow)
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
        } else {
            try {
                Start-Process -FilePath $fpath -ErrorAction Stop
            } catch {
                Write-Host "Could not open: $fpath" -ForegroundColor Red
            }
        }
        return $true
    }

    try {
        Refresh-Dfile
        Draw-Dfile

        while ($true) {
            [ConsoleInput]::ReadConsoleInput($handle, [ref]$record, 1, [ref]$eventsRead) | Out-Null
            if ($record.EventType -ne 1) { continue }
            if (-not $record.KeyEvent.bKeyDown) { continue }

            $vk = $record.KeyEvent.wVirtualKeyCode
            $ch = $record.KeyEvent.UnicodeChar

            switch ($vk) {
                37 { Move-DfileH -1 }
                39 { Move-DfileH 1 }
                38 {
                    $root = [System.IO.Path]::GetPathRoot($cwd)
                    if ($cwd -ne $root -and $parent -and $parent -ne $cwd) {
                        [void](Go-DfileDir $parent)
                    }
                }
                40 {
                    if ($focus -eq 'children' -and $children.Count -gt 0) {
                        $dest = Join-Path $cwd $children[$selC]
                        [void](Go-DfileDir $dest)
                    }
                }
                9 { Toggle-DfileFocus }
                13 {
                    if ($focus -eq 'files') {
                        if (Open-SelectedFile) { return $true }
                    } else {
                        if (Exit-ToSelectedDir) { return $true }
                    }
                }
                27 {
                    Clear-DfileArea
                    [Console]::SetCursorPosition(0, $startRow)
                    return $false
                }
                default {
                    if ($ch -eq 'h' -or $ch -eq 'H') { Move-DfileH -1 }
                    elseif ($ch -eq 'l' -or $ch -eq 'L') { Move-DfileH 1 }
                    elseif ($ch -eq 'k' -or $ch -eq 'K') {
                        $root = [System.IO.Path]::GetPathRoot($cwd)
                        if ($cwd -ne $root -and $parent -and $parent -ne $cwd) {
                            [void](Go-DfileDir $parent)
                        }
                    }
                    elseif ($ch -eq 'j' -or $ch -eq 'J') {
                        if ($focus -eq 'children' -and $children.Count -gt 0) {
                            $dest = Join-Path $cwd $children[$selC]
                            [void](Go-DfileDir $dest)
                        }
                    }
                    elseif ($ch -eq 'f' -or $ch -eq 'F') { Toggle-DfileFocus }
                    elseif ($ch -eq '.') {
                        $script:showHidden = -not $showHidden
                        Refresh-Dfile
                        Draw-Dfile
                    }
                    elseif ($ch -eq '/' -or $ch -eq 's' -or $ch -eq 'S') {
                        if (Get-Command dsearch -ErrorAction SilentlyContinue) {
                            Clear-DfileArea
                            [Console]::SetCursorPosition(0, $startRow)
                            [ConsoleInput]::SetConsoleMode($handle, $mode) | Out-Null
                            $nav = dsearch
                            $newMode = ($mode -band (-bnot [ConsoleInput]::ENABLE_QUICK_EDIT_MODE)) -bor [ConsoleInput]::ENABLE_EXTENDED_FLAGS
                            [ConsoleInput]::SetConsoleMode($handle, $newMode) | Out-Null
                            if ($nav) { return $true }
                            for ($i = 0; $i -lt 4; $i++) { [Console]::WriteLine() }
                            $startRow = [Console]::CursorTop - 4
                            Refresh-Dfile
                            Draw-Dfile
                        }
                    }
                }
            }
        }
    }
    finally {
        [ConsoleInput]::SetConsoleMode($handle, $mode) | Out-Null
    }
}
