# djump.ps1 - directory jump table for DNav (PowerShell / Windows)
#
# Data file (first match wins):
#   $env:DNAV_JUMPS
#   Documents\WindowsPowerShell\dnav\config\jumps
#   Documents\WindowsPowerShell\dnav\jumps  (package install)
#
# Commands:
#   djump [-Reload|-List|KEY]   reload / list / go
#   dhome, ddoc, ...            auto-generated from keys
#   dfavorite add|edit|remove|list

$script:DjumpMap = @{}
$script:DjumpKeys = [System.Collections.Generic.List[string]]::new()
$script:DjumpLoaded = $false
$script:DjumpInstalled = [System.Collections.Generic.List[string]]::new()

# Capture install dir at source time ($PSScriptRoot only reliable while loading)
$script:DjumpSourceDir = $null
if ($PSScriptRoot) {
    $script:DjumpSourceDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $script:DjumpSourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function Get-DjumpPackageDir {
    if ($script:DnavInstallDir -and (Test-Path -LiteralPath $script:DnavInstallDir)) {
        return $script:DnavInstallDir
    }
    if ($env:DNAV_HOME -and (Test-Path -LiteralPath $env:DNAV_HOME)) {
        return [System.IO.Path]::GetFullPath($env:DNAV_HOME)
    }
    if ($script:DjumpSourceDir -and (Test-Path -LiteralPath $script:DjumpSourceDir)) {
        return $script:DjumpSourceDir
    }
    if ($PSScriptRoot) { return $PSScriptRoot }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
    return (Join-Path $docs 'WindowsPowerShell\dnav')
}

function Get-DjumpUserPath {
    if ($env:DNAV_JUMPS) { return $env:DNAV_JUMPS }
    $cfg = if ($env:DNAV_CONFIG_DIR) {
        $env:DNAV_CONFIG_DIR
    } else {
        Join-Path (Get-DjumpPackageDir) 'config'
    }
    if (-not (Test-Path -LiteralPath $cfg)) {
        New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    }
    return (Join-Path $cfg 'jumps')
}

function Get-DjumpDataPath {
    if ($env:DNAV_JUMPS -and (Test-Path -LiteralPath $env:DNAV_JUMPS)) {
        return $env:DNAV_JUMPS
    }
    $user = Get-DjumpUserPath
    if (Test-Path -LiteralPath $user) { return $user }
    $pkg = Join-Path (Get-DjumpPackageDir) 'jumps'
    if (Test-Path -LiteralPath $pkg) { return $pkg }
    return $user
}

function Expand-DjumpPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $null }
    if ($Path -eq '~') { return $env:USERPROFILE }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\')) {
        return (Join-Path $env:USERPROFILE $Path.Substring(2))
    }
    if ($Path -eq '..') {
        $parent = Split-Path -Parent (Get-Location).Path
        if ($parent) { return $parent }
        return (Get-Location).Path
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

function Format-DjumpStorePath {
    param([string]$Path)
    $full = Expand-DjumpPath $Path
    if (-not $full) { return $Path }
    $home = $env:USERPROFILE
    if ($full -eq $home) { return '~' }
    if ($full.StartsWith($home + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($home + '/', [StringComparison]::OrdinalIgnoreCase)) {
        return '~' + $full.Substring($home.Length)
    }
    return $full
}

function Test-DjumpLabel {
    param([string]$Key)
    return ($Key -match '^[A-Za-z_][A-Za-z0-9_]*$')
}

function Uninstall-DjumpCommands {
    foreach ($cmd in @($script:DjumpInstalled)) {
        Remove-Item -Path "Function:\$cmd" -ErrorAction SilentlyContinue
        Remove-Item -Path "Function:global:\$cmd" -ErrorAction SilentlyContinue
    }
    $script:DjumpInstalled.Clear()
}

function Install-DjumpCommands {
    Uninstall-DjumpCommands
    foreach ($key in $script:DjumpKeys) {
        if (-not (Test-DjumpLabel $key)) { continue }
        $cmdName = "d$key"
        $scriptBlock = [scriptblock]::Create("Invoke-DjumpGoto -Key '$key'")
        Set-Item -Path "Function:global:$cmdName" -Value $scriptBlock -Force
        $script:DjumpInstalled.Add($cmdName) | Out-Null
    }
}

function Import-DjumpTable {
    $f = Get-DjumpDataPath
    $script:DjumpMap = @{}
    $script:DjumpKeys = [System.Collections.Generic.List[string]]::new()
    $script:DjumpLoaded = $false

    if (-not (Test-Path -LiteralPath $f)) {
        Uninstall-DjumpCommands
        return $false
    }

    Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | ForEach-Object {
        $line = ($_ -split '#')[0].Trim()
        if (-not $line) { return }
        $parts = $line -split '\s+', 2
        if ($parts.Count -lt 2) { return }
        $key = $parts[0]
        $path = $parts[1].Trim()
        if (-not $key -or -not $path) { return }
        if ($script:DjumpMap.ContainsKey($key)) { return }
        $script:DjumpMap[$key] = $path
        $script:DjumpKeys.Add($key) | Out-Null
    }

    $script:DjumpLoaded = $true
    Install-DjumpCommands
    return $true
}

function Save-DjumpTable {
    $f = Get-DjumpUserPath
    $lines = @(
        '# djump table - key becomes dKEY (home -> dhome)'
        '# Format:  key   path'
        '#'
    )
    foreach ($k in $script:DjumpKeys) {
        if (-not $script:DjumpMap.ContainsKey($k)) { continue }
        $store = Format-DjumpStorePath $script:DjumpMap[$k]
        $lines += "$k  $store"
    }
    $lines | Set-Content -LiteralPath $f -Encoding UTF8
    $script:DjumpLoaded = $false
    [void](Import-DjumpTable)
}

function Ensure-Djump {
    if (-not $script:DjumpLoaded) {
        [void](Import-DjumpTable)
    }
}

function Resolve-DjumpKey {
    param([string]$Raw)
    Ensure-Djump
    if (-not $Raw) { return $null }

    $key = $Raw
    if ($Raw.StartsWith('d') -and $Raw.Length -gt 1) {
        $without = $Raw.Substring(1)
        if ($script:DjumpMap.ContainsKey($without)) {
            $key = $without
        } elseif ($script:DjumpMap.ContainsKey($Raw)) {
            $key = $Raw
        } else {
            return $null
        }
    } elseif (-not $script:DjumpMap.ContainsKey($key)) {
        return $null
    }

    return (Expand-DjumpPath $script:DjumpMap[$key])
}

function Invoke-DjumpGoto {
    param([Parameter(Mandatory)][string]$Key)
    $dest = Resolve-DjumpKey $Key
    if (-not $dest) {
        Write-Host "djump: unknown key: $Key" -ForegroundColor Red
        return $false
    }
    if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
        Write-Host "djump: not a directory: $dest" -ForegroundColor Red
        return $false
    }
    try {
        Set-Location -LiteralPath $dest
    } catch {
        Write-Host "djump: could not cd to $dest" -ForegroundColor Red
        return $false
    }
    $full = (Get-Location).Path
    if (Get-Command Show-DnavSuccessBar -ErrorAction SilentlyContinue) {
        Show-DnavSuccessBar $full
    } else {
        Write-Host $full -ForegroundColor Black -BackgroundColor Cyan
    }
    return $true
}

function Get-DjumpMatchKeys {
    param([string]$Query)
    Ensure-Djump
    if ([string]::IsNullOrEmpty($Query)) { return @() }
    $q = $Query.ToLowerInvariant()
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $script:DjumpKeys) {
        $kl = $k.ToLowerInvariant()
        $dkl = "d$kl"
        if ($kl.StartsWith($q) -or $dkl.StartsWith($q) -or $q -eq $kl -or $q -eq $dkl) {
            $hits.Add($k) | Out-Null
        }
    }
    return @($hits)
}

function djump {
    [CmdletBinding(DefaultParameterSetName = 'Go')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Go')]
        [string]$Key,

        [Parameter(ParameterSetName = 'List')]
        [Alias('l')]
        [switch]$List,

        [Parameter(ParameterSetName = 'Reload')]
        [Alias('r')]
        [switch]$Reload,

        [Parameter(ParameterSetName = 'Help')]
        [Alias('h')]
        [switch]$Help
    )

    if ($Help) {
        Write-Host 'usage: djump [-Reload|-List|KEY]'
        Write-Host '  -r, -Reload   reload jumps file and dKEY commands'
        Write-Host '  -l, -List     list dKEY -> path'
        Write-Host '  KEY           cd to jump (also: dKEY e.g. dhome)'
        Write-Host 'favorites: dfavorite add|edit|remove|list'
        return
    }

    if ($Reload) {
        $script:DjumpLoaded = $false
        if (Import-DjumpTable) {
            Write-Host "djump: loaded $($script:DjumpKeys.Count) jumps ($($script:DjumpInstalled.Count) commands)"
            return
        }
        Write-Host "djump: failed to load $(Get-DjumpDataPath)" -ForegroundColor Red
        return
    }

    if ($List -or [string]::IsNullOrEmpty($Key)) {
        Ensure-Djump
        if ($script:DjumpKeys.Count -eq 0) {
            Write-Host "djump: no jumps file at $(Get-DjumpDataPath)" -ForegroundColor DarkYellow
            Write-Host "djump: package dir $(Get-DjumpPackageDir)" -ForegroundColor DarkGray
            return
        }
        foreach ($k in $script:DjumpKeys) {
            Write-Host ("d{0,-14}  {1}" -f $k, $script:DjumpMap[$k])
        }
        return
    }

    [void](Invoke-DjumpGoto -Key $Key)
}

function dfavorite {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Command = '',

        [Parameter(Position = 1)]
        [string]$Label = '',

        [Parameter(Position = 2)]
        [string]$Path = ''
    )

    Ensure-Djump
    if (-not $script:DjumpLoaded) {
        $script:DjumpMap = @{}
        $script:DjumpKeys = [System.Collections.Generic.List[string]]::new()
        $script:DjumpLoaded = $true
    }

    switch -Regex ($Command) {
        '^(|-h|--help|help)$' {
            Write-Host ' dfavorite ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            Write-Host ''
            Write-Host '  dfavorite add LABEL [PATH]     add jump (default path: $PWD)'
            Write-Host '  dfavorite edit LABEL [PATH]    set path (default: $PWD)'
            Write-Host '  dfavorite remove LABEL         remove jump + dLABEL command'
            Write-Host '  dfavorite list                 list favorites'
            return
        }
        '^(list|-l|--list)$' {
            if ($script:DjumpKeys.Count -eq 0) {
                Write-Host 'dfavorite: no favorites yet (try: dfavorite add <label>)'
                return
            }
            foreach ($k in $script:DjumpKeys) {
                Write-Host ("d{0,-14}  {1}" -f $k, $script:DjumpMap[$k])
            }
            return
        }
        '^add$' {
            if (-not $Label) {
                Write-Host 'usage: dfavorite add LABEL [PATH]' -ForegroundColor Red
                return
            }
            if (-not (Test-DjumpLabel $Label)) {
                Write-Host "dfavorite: invalid label '$Label' (use letters, digits, _)" -ForegroundColor Red
                return
            }
            $target = if ($Path) { $Path } else { (Get-Location).Path }
            $dest = Expand-DjumpPath $target
            if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
                Write-Host "dfavorite: not a directory: $target" -ForegroundColor Red
                return
            }
            if ($script:DjumpMap.ContainsKey($Label)) {
                Write-Host "dfavorite: '$Label' exists (use: dfavorite edit $Label ...)" -ForegroundColor Red
                return
            }
            $script:DjumpKeys.Add($Label) | Out-Null
            $script:DjumpMap[$Label] = $dest
            Save-DjumpTable
            Write-Host "dfavorite: added d$Label -> $(Format-DjumpStorePath $dest)"
            return
        }
        '^edit$' {
            if (-not $Label) {
                Write-Host 'usage: dfavorite edit LABEL [PATH]' -ForegroundColor Red
                return
            }
            $lab = $Label
            if (-not $script:DjumpMap.ContainsKey($lab) -and $lab.StartsWith('d') -and $script:DjumpMap.ContainsKey($lab.Substring(1))) {
                $lab = $lab.Substring(1)
            }
            if (-not $script:DjumpMap.ContainsKey($lab)) {
                Write-Host "dfavorite: unknown label '$Label'" -ForegroundColor Red
                return
            }
            $target = if ($Path) { $Path } else { (Get-Location).Path }
            $dest = Expand-DjumpPath $target
            if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
                Write-Host "dfavorite: not a directory: $target" -ForegroundColor Red
                return
            }
            $script:DjumpMap[$lab] = $dest
            Save-DjumpTable
            Write-Host "dfavorite: updated d$lab -> $(Format-DjumpStorePath $dest)"
            return
        }
        '^(remove|rm|delete|del)$' {
            if (-not $Label) {
                Write-Host 'usage: dfavorite remove LABEL' -ForegroundColor Red
                return
            }
            $lab = $Label
            if (-not $script:DjumpMap.ContainsKey($lab) -and $lab.StartsWith('d') -and $script:DjumpMap.ContainsKey($lab.Substring(1))) {
                $lab = $lab.Substring(1)
            }
            if (-not $script:DjumpMap.ContainsKey($lab)) {
                Write-Host "dfavorite: unknown label '$Label'" -ForegroundColor Red
                return
            }
            $script:DjumpMap.Remove($lab) | Out-Null
            $null = $script:DjumpKeys.Remove($lab)
            Save-DjumpTable
            Write-Host "dfavorite: removed d$lab"
            return
        }
        default {
            Write-Host "dfavorite: unknown command '$Command' (try: dfavorite --help)" -ForegroundColor Red
        }
    }
}

function Initialize-DjumpDefaults {
    $user = Get-DjumpUserPath
    if (Test-Path -LiteralPath $user) { return }
    $pkg = Join-Path (Get-DjumpPackageDir) 'jumps'
    if (Test-Path -LiteralPath $pkg) {
        Copy-Item -LiteralPath $pkg -Destination $user -Force
    } else {
        @"
# djump table - key becomes dKEY (home -> dhome)
# Format:  key   path
#
home      ~
doc       ~/Documents
down      ~/Downloads
pic       ~/Pictures
desk      ~/Desktop
music     ~/Music
vid       ~/Videos
proj      ~/Projects
con       ~/.config
bk        ..
"@ | Set-Content -LiteralPath $user -Encoding UTF8
    }
}

Initialize-DjumpDefaults
[void](Import-DjumpTable)
