# djump.ps1 - directory jump table for DNav (PowerShell / Windows)
# Public commands and state use global: scope so they survive after load.
#
# Data file (first match wins):
#   $env:DNAV_JUMPS
#   Documents\WindowsPowerShell\dnav\config\jumps
#   Documents\WindowsPowerShell\dnav\jumps  (package install)
#
# Commands:
#   djump [-Reload|-List|KEY]
#   dhome, ddoc, ...
#   dfavorite add|edit|remove|list

$global:DjumpMap = @{}
$global:DjumpKeys = [System.Collections.Generic.List[string]]::new()
$global:DjumpLoaded = $false
$global:DjumpInstalled = [System.Collections.Generic.List[string]]::new()

$global:DjumpSourceDir = $null
if ($PSScriptRoot) {
    $global:DjumpSourceDir = $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    $global:DjumpSourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path
}

function global:Get-DjumpPackageDir {
    if ($global:DnavInstallDir -and (Test-Path -LiteralPath $global:DnavInstallDir)) {
        return $global:DnavInstallDir
    }
    if ($env:DNAV_HOME -and (Test-Path -LiteralPath $env:DNAV_HOME)) {
        return [System.IO.Path]::GetFullPath($env:DNAV_HOME)
    }
    if ($global:DjumpSourceDir -and (Test-Path -LiteralPath $global:DjumpSourceDir)) {
        return $global:DjumpSourceDir
    }
    if ($PSScriptRoot) { return $PSScriptRoot }
    $docs = [Environment]::GetFolderPath('MyDocuments')
    if (-not $docs) { $docs = Join-Path $env:USERPROFILE 'Documents' }
    return (Join-Path $docs 'WindowsPowerShell\dnav')
}

function global:Get-DjumpUserPath {
    if ($env:DNAV_JUMPS) { return $env:DNAV_JUMPS }
    $cfg = if ($env:DNAV_CONFIG_DIR) { $env:DNAV_CONFIG_DIR } else { Join-Path (Get-DjumpPackageDir) 'config' }
    if (-not (Test-Path -LiteralPath $cfg)) {
        New-Item -ItemType Directory -Path $cfg -Force | Out-Null
    }
    return (Join-Path $cfg 'jumps')
}

function global:Get-DjumpDataPath {
    if ($env:DNAV_JUMPS -and (Test-Path -LiteralPath $env:DNAV_JUMPS)) { return $env:DNAV_JUMPS }
    $user = Get-DjumpUserPath
    if (Test-Path -LiteralPath $user) { return $user }
    $pkg = Join-Path (Get-DjumpPackageDir) 'jumps'
    if (Test-Path -LiteralPath $pkg) { return $pkg }
    return $user
}

function global:Expand-DjumpPath {
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
    try { return [System.IO.Path]::GetFullPath((Join-Path (Get-Location).Path $expanded)) }
    catch { return (Join-Path (Get-Location).Path $expanded) }
}

function global:Format-DjumpStorePath {
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

function global:Test-DjumpLabel {
    param([string]$Key)
    return ($Key -match '^[A-Za-z_][A-Za-z0-9_]*$')
}

function global:Uninstall-DjumpCommands {
    foreach ($cmd in @($global:DjumpInstalled)) {
        Remove-Item -Path "Function:\$cmd" -ErrorAction SilentlyContinue
        Remove-Item -Path "Function:global:\$cmd" -ErrorAction SilentlyContinue
    }
    $global:DjumpInstalled.Clear()
}

function global:Install-DjumpCommands {
    Uninstall-DjumpCommands
    foreach ($key in $global:DjumpKeys) {
        if (-not (Test-DjumpLabel $key)) { continue }
        $cmdName = "d$key"
        $scriptBlock = [scriptblock]::Create("Invoke-DjumpGoto -Key '$key'")
        Set-Item -Path "Function:global:$cmdName" -Value $scriptBlock -Force
        $global:DjumpInstalled.Add($cmdName) | Out-Null
    }
}

function global:Import-DjumpTable {
    $f = Get-DjumpDataPath
    $global:DjumpMap = @{}
    $global:DjumpKeys = [System.Collections.Generic.List[string]]::new()
    $global:DjumpLoaded = $false

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
        if ($global:DjumpMap.ContainsKey($key)) { return }
        $global:DjumpMap[$key] = $path
        $global:DjumpKeys.Add($key) | Out-Null
    }

    $global:DjumpLoaded = $true
    Install-DjumpCommands
    return $true
}

function global:Save-DjumpTable {
    $f = Get-DjumpUserPath
    $lines = @(
        '# djump table - key becomes dKEY (home -> dhome)'
        '# Format:  key   path'
        '#'
    )
    foreach ($k in $global:DjumpKeys) {
        if (-not $global:DjumpMap.ContainsKey($k)) { continue }
        $store = Format-DjumpStorePath $global:DjumpMap[$k]
        $lines += "$k  $store"
    }
    $lines | Set-Content -LiteralPath $f -Encoding UTF8
    $global:DjumpLoaded = $false
    [void](Import-DjumpTable)
}

function global:Ensure-Djump {
    if (-not $global:DjumpLoaded) { [void](Import-DjumpTable) }
}

function global:Resolve-DjumpKey {
    param([string]$Raw)
    Ensure-Djump
    if (-not $Raw) { return $null }
    $key = $Raw
    if ($Raw.StartsWith('d') -and $Raw.Length -gt 1) {
        $without = $Raw.Substring(1)
        if ($global:DjumpMap.ContainsKey($without)) { $key = $without }
        elseif ($global:DjumpMap.ContainsKey($Raw)) { $key = $Raw }
        else { return $null }
    } elseif (-not $global:DjumpMap.ContainsKey($key)) {
        return $null
    }
    return (Expand-DjumpPath $global:DjumpMap[$key])
}

function global:Invoke-DjumpGoto {
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
    try { Set-Location -LiteralPath $dest }
    catch {
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

function global:Get-DjumpMatchKeys {
    param([string]$Query)
    Ensure-Djump
    if ([string]::IsNullOrEmpty($Query)) { return @() }
    $q = $Query.ToLowerInvariant()
    $hits = [System.Collections.Generic.List[string]]::new()
    foreach ($k in $global:DjumpKeys) {
        $kl = $k.ToLowerInvariant()
        $dkl = "d$kl"
        if ($kl.StartsWith($q) -or $dkl.StartsWith($q) -or $q -eq $kl -or $q -eq $dkl) {
            $hits.Add($k) | Out-Null
        }
    }
    return @($hits)
}

function global:djump {
    [CmdletBinding(DefaultParameterSetName = 'Go')]
    param(
        [Parameter(Position = 0, ParameterSetName = 'Go')][string]$Key,
        [Parameter(ParameterSetName = 'List')][Alias('l')][switch]$List,
        [Parameter(ParameterSetName = 'Reload')][Alias('r')][switch]$Reload,
        [Parameter(ParameterSetName = 'Help')][Alias('h')][switch]$Help
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
        $global:DjumpLoaded = $false
        if (Import-DjumpTable) {
            Write-Host "djump: loaded $($global:DjumpKeys.Count) jumps ($($global:DjumpInstalled.Count) commands)"
            return
        }
        Write-Host "djump: failed to load $(Get-DjumpDataPath)" -ForegroundColor Red
        return
    }
    if ($List -or [string]::IsNullOrEmpty($Key)) {
        Ensure-Djump
        if ($global:DjumpKeys.Count -eq 0) {
            Write-Host "djump: no jumps file at $(Get-DjumpDataPath)" -ForegroundColor DarkYellow
            Write-Host "djump: package dir $(Get-DjumpPackageDir)" -ForegroundColor DarkGray
            return
        }
        foreach ($k in $global:DjumpKeys) {
            Write-Host ("d{0,-14}  {1}" -f $k, $global:DjumpMap[$k])
        }
        return
    }
    [void](Invoke-DjumpGoto -Key $Key)
}

function global:dfavorite {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Command = '',
        [Parameter(Position = 1)][string]$Label = '',
        [Parameter(Position = 2)][string]$Path = ''
    )

    Ensure-Djump
    if (-not $global:DjumpLoaded) {
        $global:DjumpMap = @{}
        $global:DjumpKeys = [System.Collections.Generic.List[string]]::new()
        $global:DjumpLoaded = $true
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
            if ($global:DjumpKeys.Count -eq 0) {
                Write-Host 'dfavorite: no favorites yet (try: dfavorite add <label>)'
                return
            }
            foreach ($k in $global:DjumpKeys) {
                Write-Host ("d{0,-14}  {1}" -f $k, $global:DjumpMap[$k])
            }
            return
        }
        '^add$' {
            if (-not $Label) { Write-Host 'usage: dfavorite add LABEL [PATH]' -ForegroundColor Red; return }
            if (-not (Test-DjumpLabel $Label)) {
                Write-Host "dfavorite: invalid label '$Label' (use letters, digits, _)" -ForegroundColor Red; return
            }
            $target = if ($Path) { $Path } else { (Get-Location).Path }
            $dest = Expand-DjumpPath $target
            if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
                Write-Host "dfavorite: not a directory: $target" -ForegroundColor Red; return
            }
            if ($global:DjumpMap.ContainsKey($Label)) {
                Write-Host "dfavorite: '$Label' exists (use: dfavorite edit $Label ...)" -ForegroundColor Red; return
            }
            $global:DjumpKeys.Add($Label) | Out-Null
            $global:DjumpMap[$Label] = $dest
            Save-DjumpTable
            Write-Host "dfavorite: added d$Label -> $(Format-DjumpStorePath $dest)"
            return
        }
        '^edit$' {
            if (-not $Label) { Write-Host 'usage: dfavorite edit LABEL [PATH]' -ForegroundColor Red; return }
            $lab = $Label
            if (-not $global:DjumpMap.ContainsKey($lab) -and $lab.StartsWith('d') -and $global:DjumpMap.ContainsKey($lab.Substring(1))) {
                $lab = $lab.Substring(1)
            }
            if (-not $global:DjumpMap.ContainsKey($lab)) {
                Write-Host "dfavorite: unknown label '$Label'" -ForegroundColor Red; return
            }
            $target = if ($Path) { $Path } else { (Get-Location).Path }
            $dest = Expand-DjumpPath $target
            if (-not (Test-Path -LiteralPath $dest -PathType Container)) {
                Write-Host "dfavorite: not a directory: $target" -ForegroundColor Red; return
            }
            $global:DjumpMap[$lab] = $dest
            Save-DjumpTable
            Write-Host "dfavorite: updated d$lab -> $(Format-DjumpStorePath $dest)"
            return
        }
        '^(remove|rm|delete|del)$' {
            if (-not $Label) { Write-Host 'usage: dfavorite remove LABEL' -ForegroundColor Red; return }
            $lab = $Label
            if (-not $global:DjumpMap.ContainsKey($lab) -and $lab.StartsWith('d') -and $global:DjumpMap.ContainsKey($lab.Substring(1))) {
                $lab = $lab.Substring(1)
            }
            if (-not $global:DjumpMap.ContainsKey($lab)) {
                Write-Host "dfavorite: unknown label '$Label'" -ForegroundColor Red; return
            }
            $global:DjumpMap.Remove($lab) | Out-Null
            $null = $global:DjumpKeys.Remove($lab)
            Save-DjumpTable
            Write-Host "dfavorite: removed d$lab"
            return
        }
        default {
            Write-Host "dfavorite: unknown command '$Command' (try: dfavorite help)" -ForegroundColor Red
        }
    }
}

function global:Initialize-DjumpDefaults {
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
