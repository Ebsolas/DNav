# dsearch.ps1 - fuzzy directory search for DNav (PowerShell, cross-platform)
#
# Loaded by dnav.ps1 when present. Standalone:
#   . .\powershell\dnav.ps1   # or . dsearch.ps1 after platform
#   dsearch
#
# Index: Get-DnavCacheDir/dirs.idx (XDG on Unix, LOCALAPPDATA on Windows)
# Override roots: $env:DNAV_SEARCH_ROOTS = "/home/you;/opt"  or "C:\Users\you;D:\"

if (-not (Get-Command Get-DnavCacheDir -ErrorAction SilentlyContinue)) {
    $__p = $null
    if ($PSScriptRoot) { $__p = Join-Path $PSScriptRoot 'dnav.platform.ps1' }
    if ($__p -and (Test-Path -LiteralPath $__p)) { . $__p }
}

function global:Get-DsearchCacheDir {
    if (Get-Command Get-DnavCacheDir -ErrorAction SilentlyContinue) {
        return (Get-DnavCacheDir)
    }
    if ($env:DNAV_CACHE_DIR) { return $env:DNAV_CACHE_DIR }
    if ($env:XDG_CACHE_HOME) { return (Join-Path $env:XDG_CACHE_HOME 'dnav') }
    if ($env:LOCALAPPDATA) { return (Join-Path $env:LOCALAPPDATA 'dnav') }
    return (Join-Path ([Environment]::GetEnvironmentVariable('HOME')) '.cache/dnav')
}

function global:Get-DsearchIndexPath {
    # Separate from zsh/bash full index (dirs.idx) so light PS rebuilds don't clobber it
    return (Join-Path (Get-DsearchCacheDir) 'dirs-ps.idx')
}

function global:Test-DsearchIndexStale {
    param([string]$IndexPath)
    if (-not (Test-Path -LiteralPath $IndexPath)) { return $true }
    $item = Get-Item -LiteralPath $IndexPath -ErrorAction SilentlyContinue
    if (-not $item -or $item.Length -eq 0) { return $true }
    return ((Get-Date) - $item.LastWriteTime).TotalHours -gt 24
}

function global:Get-DsearchMaxDepth {
    if ($env:DNAV_SEARCH_MAX_DEPTH -match '^\d+$') {
        return [int]$env:DNAV_SEARCH_MAX_DEPTH
    }
    return 8
}

function global:Get-DsearchMaxPaths {
    if ($env:DNAV_SEARCH_MAX_PATHS -match '^\d+$') {
        return [int]$env:DNAV_SEARCH_MAX_PATHS
    }
    return 20000
}

function global:Get-DsearchRoots {
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

    $userHome = if (Get-Command Get-DnavUserHome -ErrorAction SilentlyContinue) {
        Get-DnavUserHome
    } elseif ($env:USERPROFILE) {
        $env:USERPROFILE
    } else {
        [Environment]::GetEnvironmentVariable('HOME')
    }

    # Default: HOME only (walk with depth/path caps). Broad roots cause multi‑GB
    # walks on Linux and immediately thrash memory. Opt into more via DNAV_SEARCH_ROOTS
    # or DNAV_SEARCH_BROAD=1.
    Add-Root $userHome

    $broad = $env:DNAV_SEARCH_BROAD
    if ($broad -eq '1' -or $broad -eq 'true' -or $broad -eq 'yes') {
        $isWin = $false
        if (Get-Command Test-DnavWindows -ErrorAction SilentlyContinue) {
            $isWin = Test-DnavWindows
        } elseif ($env:OS -eq 'Windows_NT') {
            $isWin = $true
        }
        if ($isWin) {
            Add-Root (Join-Path $userHome 'OneDrive')
            Add-Root 'D:\'
            Add-Root 'E:\'
        } else {
            Add-Root '/opt'
            Add-Root '/usr/local'
            Add-Root '/srv'
        }
    }

    return $roots
}

function global:Test-DsearchSkipDir {
    param([string]$Name)
    $skip = @(
        '.git', 'node_modules', '__pycache__', '.npm', '.cargo', '.cache',
        'target', 'vendor', '.venv', 'venv', '.tox', '.gradle', '.m2',
        'AppData', 'Application Data', 'Cookies', 'Local Settings',
        'NTUSER.DAT', 'Temp', 'tmp', '.Trash', '$Recycle.Bin', 'System Volume Information',
        'Windows', 'WinSxS', 'ProgramData', 'Recovery', 'PerfLogs',
        'proc', 'sys', 'dev', 'run', 'boot', 'lost+found',
        'Trash', 'Caches', '.local',  # .local often huge (share/containers); use DNAV_SEARCH_ROOTS for share
        'snap', 'Flatpak', 'containers', 'docker', 'podman',
        'Library', 'Application Support',
        'chromium', 'google-chrome', 'BraveSoftware', 'Code', 'Cursor',
        'discord', 'Slack', 'Steam', 'proton', 'lutris'
    )
    if ($skip -contains $Name) { return $true }
    # Prefix skips (e.g. .cache:q clones of .cache)
    if ($Name.StartsWith('.cache') -or $Name.StartsWith('.npm') -or
        $Name.StartsWith('.cargo') -or $Name.StartsWith('.rustup')) {
        return $true
    }
    # Other heavy/hidden tool trees
    if ($Name -eq '.git' -or $Name -eq '.oh-my-zsh' -or $Name -eq '.grok' -or
        $Name -eq '.vscode' -or $Name -eq '.cursor' -or $Name -eq '.pm2') {
        return $true
    }
    return $false
}

function global:Build-DsearchIndex {
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
    $maxDepth = Get-DsearchMaxDepth
    $maxPaths = Get-DsearchMaxPaths
    $count = 0
    # Stream to file — avoid keeping every path in a giant sorted list in RAM
    $sw = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.UTF8Encoding]::new($false))
    $seen = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    # stack entries: "depth`tpath"
    $stack = [System.Collections.Generic.Stack[string]]::new()

    try {
        foreach ($root in $roots) {
            if (-not (Test-Path -LiteralPath $root -PathType Container)) { continue }
            if (-not $seen.Add($root)) { continue }
            $sw.WriteLine($root)
            $count++
            $stack.Push("0`t$root")

            while ($stack.Count -gt 0) {
                if ($count -ge $maxPaths) { break }
                $entry = $stack.Pop()
                $tab = $entry.IndexOf([char]9)
                if ($tab -lt 0) { continue }
                $depth = [int]$entry.Substring(0, $tab)
                $current = $entry.Substring($tab + 1)
                if ($depth -ge $maxDepth) { continue }
                try {
                    foreach ($dir in [System.IO.Directory]::EnumerateDirectories($current)) {
                        if ($count -ge $maxPaths) { break }
                        $name = [System.IO.Path]::GetFileName($dir)
                        if (Test-DsearchSkipDir $name) { continue }
                        if (-not $seen.Add($dir)) { continue }
                        $sw.WriteLine($dir)
                        $count++
                        $stack.Push(('{0}{1}{2}' -f ($depth + 1), [char]9, $dir))
                        if ($OnProgress -and ($count % 100 -eq 0)) {
                            & $OnProgress $count
                        }
                    }
                } catch {
                    # Access denied on this node - skip children
                }
            }
            if ($count -ge $maxPaths) { break }
        }
    } finally {
        $sw.Close()
        $sw.Dispose()
    }

    if ($OnProgress) { & $OnProgress $count }
    # Optional sort without loading all as PS objects: use external sort if available
    $sortedTmp = "$tmp.sorted"
    $sortedOk = $false
    if (Get-Command sort -ErrorAction SilentlyContinue) {
        try {
            & sort -u -o $sortedTmp $tmp 2>$null
            if (Test-Path -LiteralPath $sortedTmp) {
                Move-Item -LiteralPath $sortedTmp -Destination $IndexPath -Force
                Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
                $sortedOk = $true
            }
        } catch { }
    }
    if (-not $sortedOk) {
        Move-Item -LiteralPath $tmp -Destination $IndexPath -Force
        Remove-Item -LiteralPath $sortedTmp -Force -ErrorAction SilentlyContinue
    }
    return $count
}

function global:Ensure-DsearchIndex {
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

function global:Get-DsearchFuzzyScore {
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

function global:Get-DsearchPrefix1Score {
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

function global:Invoke-DsearchFilter {
    param(
        [string]$Query,
        [string[]]$Source,
        [int]$Max = 10
    )
    if ([string]::IsNullOrEmpty($Query) -or $null -eq $Source) {
        return @()
    }

    $modePrefix1 = ($Query.Length -eq 1)
    # Bounded top-N heap (arrays) — never materialize every match as PSObject
    $topScores = New-Object 'int[]' $Max
    $topPaths = New-Object 'string[]' $Max
    $topN = 0
    $minTop = [int]::MinValue

    foreach ($path in $Source) {
        if ([string]::IsNullOrEmpty($path)) { continue }
        $sc = if ($modePrefix1) {
            Get-DsearchPrefix1Score -Path $path -Query $Query
        } else {
            Get-DsearchFuzzyScore -Path $path -Query $Query
        }
        if ($sc -lt 0) { continue }
        if ($topN -eq $Max -and $sc -le $minTop) { continue }

        if ($topN -lt $Max) {
            $i = $topN
            $topN++
        } else {
            $i = $Max - 1
        }
        while ($i -gt 0 -and $sc -gt $topScores[$i - 1]) {
            $topScores[$i] = $topScores[$i - 1]
            $topPaths[$i] = $topPaths[$i - 1]
            $i--
        }
        $topScores[$i] = $sc
        $topPaths[$i] = $path
        $minTop = $topScores[$topN - 1]
    }

    if ($topN -eq 0) { return @() }
    $out = New-Object 'string[]' $topN
    [Array]::Copy($topPaths, $out, $topN)
    return $out
}

function global:Format-DsearchPath {
    param([string]$Path, [int]$MaxWidth = 0)
    # NOTE: never assign $home — it aliases automatic read-only $HOME
    $userHome = if (Get-Command Get-DnavUserHome -ErrorAction SilentlyContinue) {
        Get-DnavUserHome
    } elseif ($env:USERPROFILE) {
        $env:USERPROFILE
    } else {
        [Environment]::GetEnvironmentVariable('HOME')
    }
    $p = $Path
    if ($userHome -and (
            $p -eq $userHome -or
            $p.StartsWith($userHome + '\', [StringComparison]::OrdinalIgnoreCase) -or
            $p.StartsWith($userHome + '/', [StringComparison]::OrdinalIgnoreCase))) {
        $p = '~' + $p.Substring($userHome.Length)
    }
    if ($MaxWidth -gt 0 -and $p.Length -gt $MaxWidth) {
        $p = [char]0x2026 + $p.Substring($p.Length - ($MaxWidth - 1))
    }
    return $p
}

function global:dsearch {
    if (-not (Get-Command Read-DnavKey -ErrorAction SilentlyContinue)) {
        function script:Read-DnavKey {
            $ki = [Console]::ReadKey($true)
            $ctrl = $false
            try { $ctrl = ($ki.Modifiers -band [ConsoleModifiers]::Control) -ne 0 } catch { }
            return [pscustomobject]@{ Key = $ki.Key; Char = $ki.KeyChar; Ctrl = $ctrl }
        }
    }

    $idx = Get-DsearchIndexPath
    if (-not (Ensure-DsearchIndex)) {
        Write-Host 'dsearch: no directory index available.' -ForegroundColor Red
        return $false
    }

    # Read as string[] once; do not re-parse on every key
    $allPaths = [System.IO.File]::ReadAllLines($idx)
    if ($null -eq $allPaths -or $allPaths.Length -eq 0) {
        Write-Host 'dsearch: index is empty.' -ForegroundColor Red
        return $false
    }
    # Soft cap interactive working set (full file may still be large from older builds)
    $maxLoad = Get-DsearchMaxPaths
    if ($allPaths.Length -gt $maxLoad) {
        $tmp = New-Object 'string[]' $maxLoad
        [Array]::Copy($allPaths, $tmp, $maxLoad)
        $allPaths = $tmp
    }

    # Shared state for nested draw/update (same pitfall as dfile: $script: vs local)
    $st = @{
        Query     = ''
        Matches   = @()
        Selected  = 0
        MaxResults = 10
        StartRow  = 0
    }

    $reserve = $st.MaxResults + 1
    for ($i = 0; $i -lt $reserve; $i++) { [Console]::WriteLine() }
    $st.StartRow = [Console]::CursorTop - $reserve

    function Clear-SearchArea {
        $winW = if (Get-Command Get-DnavConsoleWidth -ErrorAction SilentlyContinue) {
            Get-DnavConsoleWidth
        } else {
            [Math]::Max(20, [Console]::WindowWidth)
        }
        for ($r = 0; $r -le $st.MaxResults; $r++) {
            try {
                [Console]::SetCursorPosition(0, $st.StartRow + $r)
                [Console]::Write((' ' * $winW))
            } catch { }
        }
    }

    function Draw-Search {
        $winW = if (Get-Command Get-DnavConsoleWidth -ErrorAction SilentlyContinue) {
            Get-DnavConsoleWidth
        } else {
            [Math]::Max(20, [Console]::WindowWidth)
        }
        Clear-SearchArea

        try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
        # Chip: leading space + "DNav Search:" — NO trailing space (space after chip is normal text)
        # Renders like zsh: [ DNav Search:] query
        $label = ' DNav Search:'
        Write-Host $label -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        try { [Console]::Write(' ') } catch { Write-Host ' ' -NoNewline }

        $mc = @($st.Matches).Count
        $countStr = if ($mc -gt 0) { " $($st.Selected + 1)/$mc " } else { '' }
        $avail = $winW - $label.Length - 1 - $countStr.Length
        if ($avail -lt 4) { $avail = 4 }
        $qshow = [string]$st.Query
        if ($qshow.Length -gt $avail) {
            $qshow = $qshow.Substring(0, $avail - 1) + [char]0x2026
        }
        # Query as plain text (not cyan) so it doesn't look like a second chip
        if ($qshow.Length -gt 0) {
            [Console]::Write($qshow)
        }
        try {
            $pad = $winW - [Console]::CursorLeft - $countStr.Length
            if ($pad -gt 0) { [Console]::Write((' ' * $pad)) }
        } catch { }
        if ($countStr) {
            Write-Host $countStr -ForegroundColor DarkGray -NoNewline
        }

        for ($i = 0; $i -lt $mc -and $i -lt $st.MaxResults; $i++) {
            try { [Console]::SetCursorPosition(0, $st.StartRow + 1 + $i) } catch { }
            $disp = Format-DsearchPath -Path $st.Matches[$i] -MaxWidth ($winW - 4)
            if ($i -eq $st.Selected) {
                Write-Host (" > $disp".PadRight($winW)) -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            } else {
                Write-Host ("   $disp".PadRight($winW)) -ForegroundColor DarkGray -NoNewline
            }
        }
        try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
    }

    function Update-Matches {
        if ([string]::IsNullOrEmpty($st.Query)) {
            $st.Matches = @()
            $st.Selected = 0
            return
        }
        $st.Matches = @(Invoke-DsearchFilter -Query $st.Query -Source $allPaths -Max $st.MaxResults)
        $st.Selected = 0
    }

    $prevVis = $true
    try {
        try { $prevVis = [Console]::CursorVisible; [Console]::CursorVisible = $false } catch { }
        Draw-Search
        while ($true) {
            $k = Read-DnavKey
            $key = $k.Key
            $ch = $k.Char
            $mc = @($st.Matches).Count

            if ($key -eq [ConsoleKey]::UpArrow -or ($k.Ctrl -and ($ch -eq 'p' -or $ch -eq 'P'))) {
                if ($mc -gt 0 -and $st.Selected -gt 0) {
                    $st.Selected--; Draw-Search
                }
                continue
            }
            if ($key -eq [ConsoleKey]::DownArrow -or ($k.Ctrl -and ($ch -eq 'n' -or $ch -eq 'N'))) {
                if ($mc -gt 0 -and $st.Selected -lt ($mc - 1)) {
                    $st.Selected++; Draw-Search
                }
                continue
            }
            if ($key -eq [ConsoleKey]::Enter) {
                if ($mc -eq 0) { continue }
                $target = $st.Matches[$st.Selected]
                Clear-SearchArea
                try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
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
            if ($key -eq [ConsoleKey]::Escape) {
                Clear-SearchArea
                try { [Console]::SetCursorPosition(0, $st.StartRow) } catch { }
                return $false
            }
            if ($key -eq [ConsoleKey]::Backspace) {
                if ($st.Query.Length -gt 0) {
                    $st.Query = $st.Query.Substring(0, $st.Query.Length - 1)
                    Update-Matches
                    Draw-Search
                }
                continue
            }
            if ($k.Ctrl -and ($ch -eq 'u' -or $ch -eq 'U')) {
                $st.Query = ''
                Update-Matches
                Draw-Search
                continue
            }
            if ($ch -ge [char]32 -and $ch -le [char]126 -and -not $k.Ctrl) {
                $st.Query = $st.Query + [string]$ch
                Update-Matches
                Draw-Search
            }
        }
    }
    finally {
        try { [Console]::CursorVisible = $prevVis } catch { }
    }
}

function global:dsearch-reindex {
    $idx = Get-DsearchIndexPath
    Write-Host "Rebuilding index at $idx ..." -ForegroundColor Cyan
    $n = Build-DsearchIndex -IndexPath $idx -OnProgress {
        param($c)
        Write-Host "`r  $c dirs..." -NoNewline
    }
    Write-Host "`r  Done. Index written." -ForegroundColor Green
    Write-Host "  Index: $idx"
}
