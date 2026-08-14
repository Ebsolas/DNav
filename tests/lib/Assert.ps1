# Minimal assertion helpers for DNav PowerShell tests (dot-source only).
# Counters: $script:DnavTestPass / Fail / Skip / Name

if (-not (Get-Variable -Name DnavTestPass -Scope Script -ErrorAction SilentlyContinue)) {
    $script:DnavTestPass = 0
    $script:DnavTestFail = 0
    $script:DnavTestSkip = 0
    $script:DnavTestName = ''
}

function script:Dnav-TestFail {
    param([string]$Message)
    $script:DnavTestFail++
    $prefix = if ($script:DnavTestName) { "$($script:DnavTestName): " } else { '' }
    Write-Host "  FAIL  $prefix$Message" -ForegroundColor Red
}

function script:Dnav-TestPass {
    param([string]$Message = '')
    $script:DnavTestPass++
    if ($env:DNAV_TEST_VERBOSE) {
        $prefix = if ($script:DnavTestName) { "$($script:DnavTestName): " } else { '' }
        Write-Host "  ok    $prefix$Message"
    }
}

function script:Assert-Eq {
    param($Actual, $Expected, [string]$Message = 'values equal')
    if ("$Actual" -eq "$Expected") {
        Dnav-TestPass $Message
    } else {
        Dnav-TestFail "$Message (expected=$Expected actual=$Actual)"
    }
}

function script:Assert-True {
    param([bool]$Condition, [string]$Message = 'condition true')
    if ($Condition) { Dnav-TestPass $Message } else { Dnav-TestFail $Message }
}

function script:Assert-False {
    param([bool]$Condition, [string]$Message = 'condition false')
    if (-not $Condition) { Dnav-TestPass $Message } else { Dnav-TestFail $Message }
}

function script:Assert-Ok {
    param([scriptblock]$Block, [string]$Message = 'block ok')
    try {
        & $Block | Out-Null
        Dnav-TestPass $Message
    } catch {
        Dnav-TestFail "$Message ($($_.Exception.Message))"
    }
}

function script:Assert-File {
    param([string]$Path, [string]$Message = "file exists: $Path")
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        Dnav-TestPass $Message
    } else {
        Dnav-TestFail $Message
    }
}

function script:Assert-Dir {
    param([string]$Path, [string]$Message = "dir exists: $Path")
    if (Test-Path -LiteralPath $Path -PathType Container) {
        Dnav-TestPass $Message
    } else {
        Dnav-TestFail $Message
    }
}

function script:Assert-Contains {
    param([string]$Haystack, [string]$Needle, [string]$Message = 'contains')
    if ($Haystack -like "*$Needle*") {
        Dnav-TestPass $Message
    } else {
        Dnav-TestFail "$Message (missing $Needle)"
    }
}

function script:Run-Test {
    param([string]$Name, [scriptblock]$Block)
    $script:DnavTestName = $Name
    if ($env:DNAV_TEST_VERBOSE) { Write-Host "  RUN   $Name" }
    try {
        & $Block
    } catch {
        Dnav-TestFail "uncaught: $($_.Exception.Message)"
    }
    $script:DnavTestName = ''
}

function script:Skip-Test {
    param([string]$Reason = 'skipped')
    $script:DnavTestSkip++
    $prefix = if ($script:DnavTestName) { "$($script:DnavTestName): " } else { '' }
    Write-Host "  SKIP  $prefix$Reason" -ForegroundColor Yellow
}

function script:Dnav-TestFinish {
    Write-Host "# dnav-test: pass=$($script:DnavTestPass) fail=$($script:DnavTestFail) skip=$($script:DnavTestSkip)"
    if ($script:DnavTestFail -gt 0) { exit 1 }
    exit 0
}
