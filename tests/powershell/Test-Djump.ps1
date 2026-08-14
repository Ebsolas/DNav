# djump / path helpers (PowerShell)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
. (Join-Path $here '..\lib\Assert.ps1')
. (Join-Path $here '..\lib\Env.ps1')

try {
    Initialize-DnavTestEnv

    Run-Test 'Test-DjumpLabel' {
        Assert-True (Test-DjumpLabel 'home') 'home ok'
        Assert-True (Test-DjumpLabel 'my_fav') 'underscore ok'
        Assert-False (Test-DjumpLabel 'bad-label') 'hyphen rejected'
        Assert-False (Test-DjumpLabel '1bad') 'leading digit rejected'
    }

    Run-Test 'Expand-DjumpPath tilde' {
        $expanded = Expand-DjumpPath '~'
        Assert-Eq $expanded $env:USERPROFILE 'expand ~'
        $docs = Expand-DjumpPath '~/Documents'
        $want = Join-Path $env:USERPROFILE 'Documents'
        Assert-Eq $docs $want 'expand ~/Documents'
    }

    Run-Test 'Format-DjumpStorePath' {
        $docs = Join-Path $env:USERPROFILE 'Documents'
        $store = Format-DjumpStorePath $docs
        # Accept ~/Documents or ~\Documents depending on OS
        Assert-True ($store -eq '~/Documents' -or $store -eq '~\Documents' -or $store -like '~*Documents') "store=$store"
    }

    Run-Test 'Import-DjumpTable loads fixture' {
        Import-DjumpTable
        Assert-True ($global:DjumpKeys.Count -ge 3) "keys=$($global:DjumpKeys.Count)"
        Assert-True ($global:DjumpMap.ContainsKey('home')) 'has home'
        Assert-True ($global:DjumpMap.ContainsKey('doc')) 'has doc'
    }

    Run-Test 'dfavorite add/list/remove' {
        Import-DjumpTable
        $apps = Join-Path $env:USERPROFILE 'Projects'
        Push-Location $apps
        try {
            dfavorite add myfav | Out-Null
            Assert-True ($global:DjumpMap.ContainsKey('myfav')) 'myfav added'
            # dfavorite list uses Write-Host (not pipeline); assert via map + keys
            Assert-True ($global:DjumpKeys -contains 'myfav') 'myfav in keys'
            dfavorite remove myfav | Out-Null
            Assert-False ($global:DjumpMap.ContainsKey('myfav')) 'myfav removed'
        } finally {
            Pop-Location
        }
    }
}
finally {
    Remove-DnavTestEnv
}

Dnav-TestFinish
