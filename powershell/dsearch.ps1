# dsearch.ps1 - fuzzy directory search for DNav (PowerShell / Windows)
#
# Dot-source after (or with) dnav.ps1:
#   . .\powershell\dnav.ps1
#   . .\powershell\dsearch.ps1
#   dsearch          # standalone
#   dnav             # then press / or s
#
# Index cache:  $env:LOCALAPPDATA\dnav\dirs.idx  (refreshed after 24h)
# Override roots: $env:DNAV_SEARCH_ROOTS = "C:\Users\you;D:\Projects"

function Get-DsearchCacheDir {
    if ($env:DNAV_CACHE_DIR) { return $env:DNAV_CACHE_DIR }
    if ($env:XDG_CACHE_HOME) { return (Join-Path $env:XDG_CACHE_HOME 'dnav') }
    return (Join-Path $env:LOCALAPPDATA 'dnav')
}

function Get-DsearchIndexPath {
    return (Join-Path (Get-DsearchCacheDir) 'dirs.idx')
}

function Test-DsearchIndexStale {
    param([string]$IndexPath)
    if (-not (Test-Path -LiteralPath $IndexPath)) { return $true }
    $item = Get-Item -LiteralPath $IndexPath -ErrorAction SilentlyContinue
    if (-not $item -or $item.Length -eq 0) { return $true }
    return ((Get-Date) - $item.LastWriteTime).TotalHours -gt 24
}

function Get-DsearchRoots {
    $roots = [System.Collections.Generic.List[string]]::new()
    $seen = @{}

    function Add-Root([string]$p) {
        if ([string]::IsNullOrWhiteSpace($p)) { return }
        if (-not (Test-Path -LiteralPath $p -PathType Container)) { return }
        try { $full = [System.IO.Path]::GetFullPath($p) } catch { return }
        if ($seen.ContainsKey($full)) { return }
        $seen[$full] = $true
        $roots.Add($full) | Out-Null
    }

    if ($env:DNAV_SEARCH_ROOTS) {
        foreach ($r in ($env:DNAV_SEARCH_ROOTS -split '[;,]')) {
            Add-Root $r.Trim()
        }
        return $roots
    }

    Add-Root $env:USERPROFILE
    Add-Root (Join-Path $env:USERPROFILE 'Documents')
    Add-Root (Join-Path $env:USERPROFILE 'Downloads')
    Add-Root (Join-Path $env:USERPROFILE 'Desktop')
    Add-Root (Join-Path $env:USERPROFILE 'Projects')
    Add-Root (Join-Path $env:USERPROFILE 'source')
    Add-Root (Join-Path $env:USERPROFILE 'dev')
    Add-Root (Join-Path $env:USERPROFILE 'OneDrive')
    Add-Root 'C:\Users'
    Add-Root 'D:\'
    Add-Root 'E:\'

    return $roots
}

function Test-DsearchSkipDir {
    param([string]$Name)
    $skip = @(
        '.git', 'node_modules', '__pycache__', '.npm', '.cargo', '.cache',
        'target', 'vendor', '.venv', 'venv', '.tox', '.gradle', '.m2',
        'AppData', 'Application Data', 'Cookies', 'Local Settings',
        'NTUSER.DAT', 'Temp', 'tmp', '.Trash', '$Recycle.Bin', 'System Volume Information',
        'Windows', 'WinSxS', 'ProgramData', 'Recovery', 'PerfLogs'
    )
    return $skip -contains $Name
}

function Build-DsearchIndex {
    param(
        [string]$IndexPath,
        [scriptblock]$OnProgress = $null
    )
    $cacheDir = Split-Path -Parent $IndexPath
    if (-not (Test-Path -LiteralPath $cacheDir)) {
        New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null
    }

    $tmp = "$IndexPath.tmp.$PID"
    $roots = Get-DsearchRoots
    $count = 0
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $stack = [System.Collections.Generic.Stack[string]]::new()

    foreach ($root in $roots) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
        [void]$paths.Add($root)
        $stack.Push($root)

        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            try {
                foreach ($dir in [System.IO.Directory]::EnumerateDirectories($current)) {
                    $name = [System.IO.Path]::GetFileName($dir)
                    if (Test-DsearchSkipDir $name) { continue }
                    if ($paths.Add($dir)) {
                        $count++
                        $stack.Push($dir)
                        if ($OnProgress -and ($count % 50 -eq 0)) {
                            & $OnProgress $count
                        }
                    }
                }
            } catch {
                # Access denied on this node - skip children
            }
        }
    }

    $sorted = $paths | Sort-Object
    $sorted | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $IndexPath -Force
    return $count
}

function Ensure-DsearchIndex {
    $idx = Get-DsearchIndexPath
    if (-not (Test-DsearchIndexStale $idx)) {
        return $true
    }

    $winW = [Math]::Max(20, [Console]::WindowWidth)
    Write-Host (" Indexing...".PadRight($winW)) -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    [Console]::SetCursorPosition(0, [Console]::CursorTop)

    $script:__dsearchCount = 0
    try {
        $null = Build-DsearchIndex -IndexPath $idx -OnProgress {
            param($n)
            $script:__dsearchCount = $n
            $msg = " Indexing... $n"
            Write-Host ($msg.PadRight([Console]::WindowWidth)) -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            [Console]::SetCursorPosition(0, [Console]::CursorTop)
        }
        Write-Host ((' ' * [Console]::WindowWidth)) -NoNewline
        [Console]::SetCursorPosition(0, [Console]::CursorTop)
        return (Test-Path -LiteralPath $idx)
    } catch {
        Write-Host " Index failed: $_" -ForegroundColor Red
        return $false
    }
}

function Get-DsearchFuzzyScore {
    param([string]$Path, [string]$Query)
    if ([string]::IsNullOrEmpty($Query)) { return -1 }
    $lp = $Path.ToLowerInvariant()
    $q = $Query.ToLowerInvariant()
    $qlen = $q.Length
    $plen = $lp.Length
    $score = 0
    $run = 0
    $last = -2
    $pi = 0

    for ($qi = 0; $qi -lt $qlen; $qi++) {
        $ch = $q[$qi]
        $found = $false
        for (; $pi -lt $plen; $pi++) {
            if ($lp[$pi] -eq $ch) {
                $found = $true
                if ($pi -eq ($last + 1)) {
                    $run++
                    $score += 8 + $run
                } else {
                    $run = 0
                    $score += 2
                }
                $prev = if ($pi -eq 0) { [char]0 } else { $lp[$pi - 1] }
                if ($pi -eq 0 -or $prev -eq '\' -or $prev -eq '/') { $score += 12 }
                if ($prev -eq '-' -or $prev -eq '_' -or $prev -eq '.') { $score += 4 }
                $last = $pi
                $pi++
                break
            }
        }
        if (-not $found) { return -1 }
    }
    $score += 40 - [Math]::Min($plen, 40)
    return $score
}

function Get-DsearchPrefix1Score {
    param([string]$Path, [string]$Query)
    if ([string]::IsNullOrEmpty($Query)) { return -1 }
    $ch = [char]::ToLowerInvariant($Query[0])
    $lp = $Path.ToLowerInvariant()
    $segs = $lp.Split([char[]]@('\', '/'), [StringSplitOptions]::RemoveEmptyEntries)
    $best = -1
    for ($i = 0; $i -lt $segs.Count; $i++) {
        $seg = $segs[$i]
        if ($seg.Length -eq 0) { continue }
        if ($seg[0] -eq $ch) {
            $sc = 50
            $sc += 20 - [Math]::Min($seg.Length, 20)
            $sc += 30 - [Math]::Min($lp.Length, 30)
            if ($i -eq ($segs.Count - 1)) { $sc += 15 }
            if ($sc -gt $best) { $best = $sc }
        }
    }
    return $best
}

function Invoke-DsearchFilter {
    param(
        [string]$Query,
        [string[]]$Source,
        [int]$Max = 10
    )
    if ([string]::IsNullOrEmpty($Query) -or $null -eq $Source) {
        return @()
    }

    $modePrefix1 = ($Query.Length -eq 1)
    $scored = [System.Collections.Generic.List[object]]::new()

    foreach ($path in $Source) {
        if ([string]::IsNullOrEmpty($path)) { continue }
        $sc = if ($modePrefix1) {
            Get-DsearchPrefix1Score -Path $path -Query $Query
        } else {
            Get-DsearchFuzzyScore -Path $path -Query $Query
        }
        if ($sc -lt 0) { continue }
        $scored.Add([pscustomobject]@{ Score = $sc; Path = $path }) | Out-Null
    }

    return @(
        $scored |
            Sort-Object -Property Score -Descending |
            Select-Object -First $Max |
            ForEach-Object { $_.Path }
    )
}

function Format-DsearchPath {
    param([string]$Path, [int]$MaxWidth = 0)
    $home = $env:USERPROFILE
    $p = $Path
    if ($p -eq $home -or $p.StartsWith($home + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $p.StartsWith($home + '/', [StringComparison]::OrdinalIgnoreCase)) {
        $p = '~' + $p.Substring($home.Length)
    }
    if ($MaxWidth -gt 0 -and $p.Length -gt $MaxWidth) {
        $p = [char]0x2026 + $p.Substring($p.Length - ($MaxWidth - 1))
    }
    return $p
}

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

function dsearch {
    Ensure-ConsoleInputType

    $idx = Get-DsearchIndexPath
    if (-not (Ensure-DsearchIndex)) {
        Write-Host 'dsearch: no directory index available.' -ForegroundColor Red
        return $false
    }

    $allPaths = @(Get-Content -LiteralPath $idx -ErrorAction SilentlyContinue)
    if ($allPaths.Count -eq 0) {
        Write-Host 'dsearch: index is empty.' -ForegroundColor Red
        return $false
    }

    $query = ''
    $matches = @()
    $selected = 0
    $maxResults = 10

    $handle = [ConsoleInput]::GetStdHandle([ConsoleInput]::STD_INPUT_HANDLE)
    $mode = 0
    [ConsoleInput]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    $newMode = ($mode -band (-bnot [ConsoleInput]::ENABLE_QUICK_EDIT_MODE)) -bor [ConsoleInput]::ENABLE_EXTENDED_FLAGS
    [ConsoleInput]::SetConsoleMode($handle, $newMode) | Out-Null

    $reserve = $maxResults + 1
    for ($i = 0; $i -lt $reserve; $i++) { [Console]::WriteLine() }
    $startRow = [Console]::CursorTop - $reserve

    $record = New-Object ConsoleInput+INPUT_RECORD
    $eventsRead = 0

    function Clear-SearchArea {
        $winW = [Console]::WindowWidth
        for ($r = 0; $r -le $maxResults; $r++) {
            [Console]::SetCursorPosition(0, $startRow + $r)
            [Console]::Write((' ' * $winW))
        }
    }

    function Draw-Search {
        $winW = [Console]::WindowWidth
        Clear-SearchArea

        [Console]::SetCursorPosition(0, $startRow)
        $label = ' DNav Search: '
        Write-Host $label -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        $countStr = if ($matches.Count -gt 0) { " $($selected+1)/$($matches.Count) " } else { '' }
        $avail = $winW - $label.Length - $countStr.Length - 1
        if ($avail -lt 4) { $avail = 4 }
        $qshow = $query
        if ($qshow.Length -gt $avail) {
            $qshow = $qshow.Substring(0, $avail - 1) + [char]0x2026
        }
        Write-Host $qshow -NoNewline
        $pad = $winW - [Console]::CursorLeft - $countStr.Length
        if ($pad -gt 0) { [Console]::Write((' ' * $pad)) }
        if ($countStr) {
            Write-Host $countStr -ForegroundColor DarkGray -NoNewline
        }

        for ($i = 0; $i -lt $matches.Count -and $i -lt $maxResults; $i++) {
            [Console]::SetCursorPosition(0, $startRow + 1 + $i)
            $disp = Format-DsearchPath -Path $matches[$i] -MaxWidth ($winW - 4)
            if ($i -eq $selected) {
                Write-Host (" > $disp".PadRight($winW)) -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            } else {
                Write-Host ("   $disp".PadRight($winW)) -ForegroundColor DarkGray -NoNewline
            }
        }
        [Console]::SetCursorPosition(0, $startRow)
    }

    function Update-Matches {
        if ([string]::IsNullOrEmpty($query)) {
            $script:matches = @()
            $script:selected = 0
            return
        }
        $script:matches = @(Invoke-DsearchFilter -Query $query -Source $allPaths -Max $maxResults)
        $script:selected = 0
    }

    try {
        Draw-Search
        while ($true) {
            [ConsoleInput]::ReadConsoleInput($handle, [ref]$record, 1, [ref]$eventsRead) | Out-Null
            if ($record.EventType -ne 1) { continue }
            if (-not $record.KeyEvent.bKeyDown) { continue }

            $vk = $record.KeyEvent.wVirtualKeyCode
            $ch = $record.KeyEvent.UnicodeChar

            switch ($vk) {
                38 {
                    if ($matches.Count -gt 0 -and $selected -gt 0) {
                        $selected--; Draw-Search
                    }
                }
                40 {
                    if ($matches.Count -gt 0 -and $selected -lt ($matches.Count - 1)) {
                        $selected++; Draw-Search
                    }
                }
                13 {
                    if ($matches.Count -eq 0) { continue }
                    $target = $matches[$selected]
                    Clear-SearchArea
                    [Console]::SetCursorPosition(0, $startRow)
                    if (Test-Path -LiteralPath $target -PathType Container) {
                        Set-Location -LiteralPath $target
                        $full = (Get-Location).Path
                        if (Get-Command Show-DnavSuccessBar -ErrorAction SilentlyContinue) {
                            Show-DnavSuccessBar $full
                        } else {
                            Write-Host $full -ForegroundColor Black -BackgroundColor Cyan
                        }
                        return $true
                    } else {
                        Write-Host "Folder not found: $target" -ForegroundColor Red
                        return $false
                    }
                }
                27 {
                    Clear-SearchArea
                    [Console]::SetCursorPosition(0, $startRow)
                    return $false
                }
                8 {
                    if ($query.Length -gt 0) {
                        $query = $query.Substring(0, $query.Length - 1)
                        Update-Matches
                        Draw-Search
                    }
                }
                default {
                    $ctrl = ($record.KeyEvent.dwControlKeyState -band 0x0C) -ne 0
                    if ($ctrl -and ($ch -eq 'u' -or $ch -eq 'U')) {
                        $query = ''
                        Update-Matches
                        Draw-Search
                        continue
                    }
                    if ($ctrl -and ($ch -eq 'n' -or $ch -eq 'N')) {
                        if ($matches.Count -gt 0 -and $selected -lt ($matches.Count - 1)) {
                            $selected++; Draw-Search
                        }
                        continue
                    }
                    if ($ctrl -and ($ch -eq 'p' -or $ch -eq 'P')) {
                        if ($matches.Count -gt 0 -and $selected -gt 0) {
                            $selected--; Draw-Search
                        }
                        continue
                    }
                    if ($ch -ge [char]32 -and $ch -le [char]126) {
                        $query += $ch
                        Update-Matches
                        Draw-Search
                    }
                }
            }
        }
    }
    finally {
        [ConsoleInput]::SetConsoleMode($handle, $mode) | Out-Null
    }
}

function dsearch-reindex {
    $idx = Get-DsearchIndexPath
    Write-Host "Rebuilding index at $idx ..." -ForegroundColor Cyan
    $n = Build-DsearchIndex -IndexPath $idx -OnProgress {
        param($c)
        Write-Host "`r  $c dirs..." -NoNewline
    }
    Write-Host "`r  Done. Index written." -ForegroundColor Green
    Write-Host "  Index: $idx"
}
