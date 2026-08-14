# dsearch pure helpers (no interactive TUI)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here '..\lib\Assert.ps1')
. (Join-Path $here '..\lib\Env.ps1')

try {
    Initialize-DnavTestEnv

    Run-Test 'dsearch commands loaded' {
        Assert-True ($null -ne (Get-Command dsearch -ErrorAction SilentlyContinue)) 'dsearch'
        Assert-True ($null -ne (Get-Command Invoke-DsearchFilter -ErrorAction SilentlyContinue)) 'filter'
        Assert-True ($null -ne (Get-Command Get-DsearchRoots -ErrorAction SilentlyContinue)) 'roots'
    }

    Run-Test 'fuzzy filter finds docs' {
        $uh = Get-DnavUserHome
        $src = @(
            $uh
            (Join-Path $uh 'Documents')
            (Join-Path $uh 'Projects')
            '/usr/share/doc'
            '/tmp/other'
        )
        $hits = @(Invoke-DsearchFilter -Query 'doc' -Source $src -Max 10)
        Assert-True ($hits.Count -gt 0) 'has hits'
        $joined = $hits -join '|'
        Assert-True ($joined -like '*Documents*' -or $joined -like '*doc*') "hits=$joined"
    }

    Run-Test 'prefix1 filter' {
        $uh = Get-DnavUserHome
        $src = @($uh, (Join-Path $uh 'Documents'), (Join-Path $uh 'Downloads'), (Join-Path $uh 'Projects'))
        $hits = @(Invoke-DsearchFilter -Query 'd' -Source $src -Max 10)
        Assert-True ($hits.Count -gt 0) 'prefix d has hits'
    }

    Run-Test 'empty query clears' {
        $hits = @(Invoke-DsearchFilter -Query '' -Source @('/tmp/a') -Max 5)
        Assert-Eq $hits.Count 0 'empty query'
    }

    Run-Test 'roots include home' {
        $roots = @(Get-DsearchRoots)
        Assert-True ($roots.Count -ge 1) 'at least one root'
        $uh = Get-DnavUserHome
        $found = $false
        foreach ($r in $roots) {
            if ($r -eq $uh) { $found = $true; break }
        }
        Assert-True $found "home in roots ($($roots -join ', '))"
    }

    Run-Test 'format path tilde' {
        $uh = Get-DnavUserHome
        $fmt = Format-DsearchPath -Path (Join-Path $uh 'Documents')
        Assert-True ($fmt -eq '~/Documents' -or $fmt -eq '~\Documents' -or $fmt -like '~*Documents') "fmt=$fmt"
    }

    Run-Test 'cache path under isolated or xdg' {
        $cache = Get-DsearchCacheDir
        Assert-True ($cache.Length -gt 0) "cache=$cache"
    }
}
finally {
    Remove-DnavTestEnv
}

Dnav-TestFinish
