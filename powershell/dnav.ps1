# dnav.ps1 - folder navigation bar for PowerShell (Windows)
#
# Dot-source into your session:
#   . .\powershell\dnav.ps1
#   dnav
#
# Keys: Left/Right or h/l  move | Enter open | Esc cancel
#
# Config (created on first run):
#   $env:APPDATA\dnav\folders   - Label  Path  (one per line)
#   $env:APPDATA\dnav\config    - simple key = value settings

function Get-DnavConfigDir {
    if ($env:DNAV_CONFIG_DIR) { return $env:DNAV_CONFIG_DIR }
    if ($env:XDG_CONFIG_HOME) { return (Join-Path $env:XDG_CONFIG_HOME 'dnav') }
    return (Join-Path $env:APPDATA 'dnav')
}

function Initialize-DnavConfig {
    $dir = Get-DnavConfigDir
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $foldersFile = Join-Path $dir 'folders'
    if (-not (Test-Path -LiteralPath $foldersFile)) {
        @"
# Main dnav bar - Label  Path  (one per line)
# Paths may use ~ for `$HOME / `$env:USERPROFILE
Home        ~
Docs        ~/Documents
Down        ~/Downloads
Pics        ~/Pictures
Desktop     ~/Desktop
Music       ~/Music
Videos      ~/Videos
Config      ~/.config
"@ | Set-Content -LiteralPath $foldersFile -Encoding UTF8
    }

    $configFile = Join-Path $dir 'config'
    if (-not (Test-Path -LiteralPath $configFile)) {
        @"
# DNav settings
brand = DNav
ls_after = 0
"@ | Set-Content -LiteralPath $configFile -Encoding UTF8
    }
}

function Expand-DnavPath {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or $Path -eq '-') { return $null }
    if ($Path -eq '~') {
        return $env:USERPROFILE
    }
    if ($Path.StartsWith('~/') -or $Path.StartsWith('~\') ) {
        return (Join-Path $env:USERPROFILE $Path.Substring(2))
    }
    return [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-DnavFolders {
    Initialize-DnavConfig
    $foldersFile = Join-Path (Get-DnavConfigDir) 'folders'
    $list = @()

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
        $list = @(
            [pscustomobject]@{ Name = 'Home';    Path = $env:USERPROFILE }
            [pscustomobject]@{ Name = 'Docs';    Path = [Environment]::GetFolderPath('MyDocuments') }
            [pscustomobject]@{ Name = 'Down';    Path = (Join-Path $env:USERPROFILE 'Downloads') }
            [pscustomobject]@{ Name = 'Pics';    Path = [Environment]::GetFolderPath('MyPictures') }
            [pscustomobject]@{ Name = 'Desktop'; Path = [Environment]::GetFolderPath('Desktop') }
            [pscustomobject]@{ Name = 'Music';   Path = [Environment]::GetFolderPath('MyMusic') }
            [pscustomobject]@{ Name = 'Videos';  Path = [Environment]::GetFolderPath('MyVideos') }
        )
    }

    # Always append About (empty path = help overlay)
    $list += [pscustomobject]@{ Name = 'About'; Path = $null }
    return $list
}

function Get-DnavBrand {
    $configFile = Join-Path (Get-DnavConfigDir) 'config'
    $brand = 'DNav'
    if (Test-Path -LiteralPath $configFile) {
        Get-Content -LiteralPath $configFile -ErrorAction SilentlyContinue | ForEach-Object {
            $line = ($_ -split '#')[0].Trim()
            if ($line -match '^\s*brand\s*=\s*(.+)$') {
                $brand = $Matches[1].Trim().Trim('"', "'")
            }
        }
    }
    return $brand
}

function Show-DnavSuccessBar {
    param([string]$Path)
    $w = [Math]::Max(20, [Console]::WindowWidth)
    $display = $Path
    if ($display.Length -gt $w) {
        $display = $display.Substring(0, $w - 1) + [char]0x2026
    }
    Write-Host ($display.PadRight($w)) -ForegroundColor Black -BackgroundColor Cyan
}

function Show-DnavAbout {
    Write-Host ''
    Write-Host ' DNav About ' -ForegroundColor Black -BackgroundColor Cyan -NoNewline
    Write-Host ''
    Write-Host '  Left/Right or h/l   move on the bar'
    Write-Host '  Enter               open selected folder'
    Write-Host '  Enter on About      this help'
    Write-Host '  Esc                 cancel / leave'
    Write-Host '  Config dir          ' -NoNewline
    Write-Host (Get-DnavConfigDir) -ForegroundColor DarkGray
    Write-Host '  Edit folders        notepad (Get-DnavConfigDir)\folders'
    Write-Host ''
}

function dnav {
    # P/Invoke console input (keyboard only - no mouse)
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

    $items = @(Get-DnavFolders)
    $brand = Get-DnavBrand
    $selected = 0

    try {
        $currentPath = [System.IO.Path]::GetFullPath((Get-Location).Path)
        for ($i = 0; $i -lt $items.Count; $i++) {
            if (-not $items[$i].Path) { continue }
            try {
                $p = [System.IO.Path]::GetFullPath($items[$i].Path)
                if ($p -eq $currentPath) { $selected = $i; break }
            } catch { }
        }
    } catch {
        $selected = 0
    }

    $handle = [ConsoleInput]::GetStdHandle([ConsoleInput]::STD_INPUT_HANDLE)
    $mode = 0
    [ConsoleInput]::GetConsoleMode($handle, [ref]$mode) | Out-Null
    # Disable Quick Edit so keyboard stays responsive; do not enable mouse
    $newMode = ($mode -band (-bnot [ConsoleInput]::ENABLE_QUICK_EDIT_MODE)) -bor [ConsoleInput]::ENABLE_EXTENDED_FLAGS
    [ConsoleInput]::SetConsoleMode($handle, $newMode) | Out-Null

    if ([Console]::BufferHeight -lt 3) {
        Write-Host 'Console buffer too small for dnav.' -ForegroundColor Red
        return
    }

    [Console]::WriteLine()
    [Console]::WriteLine()
    $startRow = [Console]::CursorTop - 2

    $record = New-Object ConsoleInput+INPUT_RECORD
    $eventsRead = 0

    function Redraw {
        $winW = [Console]::WindowWidth
        [Console]::SetCursorPosition(0, $startRow)
        $header = " $brand "
        Write-Host $header -ForegroundColor Black -BackgroundColor Cyan -NoNewline
        Write-Host '  (h/l or arrows  Enter  Esc)' -ForegroundColor DarkGray -NoNewline
        $clearLen = $winW - [Console]::CursorLeft
        if ($clearLen -gt 0) { [Console]::Write((' ' * $clearLen)) }

        [Console]::SetCursorPosition(0, $startRow + 1)
        [Console]::Write((' ' * $winW))

        $col = 1
        for ($i = 0; $i -lt $items.Count; $i++) {
            $name = $items[$i].Name
            if (($col + $name.Length + 2) -ge $winW) { break }
            [Console]::SetCursorPosition($col, $startRow + 1)
            if ($i -eq $selected) {
                Write-Host (" $name ") -ForegroundColor Black -BackgroundColor Cyan -NoNewline
            } else {
                Write-Host (" $name ") -NoNewline
            }
            $col += $name.Length + 3
        }
        [Console]::SetCursorPosition(0, $startRow + 2)
    }

    function Navigate-Selected {
        $item = $items[$selected]
        if (-not $item.Path) {
            # About
            [Console]::SetCursorPosition(0, $startRow)
            for ($r = 0; $r -lt 3; $r++) {
                [Console]::Write((' ' * [Console]::WindowWidth))
                if ($r -lt 2) { [Console]::WriteLine() }
            }
            [Console]::SetCursorPosition(0, $startRow)
            Show-DnavAbout
            return
        }
        $path = $item.Path
        if (Test-Path -LiteralPath $path -PathType Container) {
            Set-Location -LiteralPath $path
            $full = (Get-Location).Path
            [Console]::SetCursorPosition(0, $startRow)
            for ($r = 0; $r -lt 3; $r++) {
                [Console]::Write((' ' * [Console]::WindowWidth))
                if ($r -lt 2) { [Console]::WriteLine() }
            }
            [Console]::SetCursorPosition(0, $startRow)
            Show-DnavSuccessBar $full
        } else {
            Write-Host "`nFolder not found: $path" -ForegroundColor Red
        }
    }

    try {
        Redraw
        while ($true) {
            [ConsoleInput]::ReadConsoleInput($handle, [ref]$record, 1, [ref]$eventsRead) | Out-Null
            if ($record.EventType -ne 1) { continue }
            if (-not $record.KeyEvent.bKeyDown) { continue }

            $vk = $record.KeyEvent.wVirtualKeyCode
            $ch = $record.KeyEvent.UnicodeChar

            switch ($vk) {
                37 { # Left
                    if ($selected -gt 0) { $selected--; Redraw }
                }
                39 { # Right
                    if ($selected -lt ($items.Count - 1)) { $selected++; Redraw }
                }
                13 { # Enter
                    Navigate-Selected
                    return
                }
                27 { # Esc
                    [Console]::SetCursorPosition(0, $startRow)
                    for ($r = 0; $r -lt 3; $r++) {
                        [Console]::Write((' ' * [Console]::WindowWidth))
                        if ($r -lt 2) { [Console]::WriteLine() }
                    }
                    [Console]::SetCursorPosition(0, $startRow)
                    return
                }
                default {
                    # h / l as vim-style alternatives
                    if ($ch -eq 'h' -or $ch -eq 'H') {
                        if ($selected -gt 0) { $selected--; Redraw }
                    }
                    elseif ($ch -eq 'l' -or $ch -eq 'L') {
                        if ($selected -lt ($items.Count - 1)) { $selected++; Redraw }
                    }
                }
            }
        }
    }
    finally {
        # Restore previous console mode
        [ConsoleInput]::SetConsoleMode($handle, $mode) | Out-Null
    }
}

# Optional: quick help
function dhelp {
    Write-Host 'DNav (PowerShell)' -ForegroundColor Cyan
    Write-Host '  dnav          open the folder bar'
    Write-Host '  dhelp         this text'
    Write-Host "  config dir    $(Get-DnavConfigDir)"
    Write-Host '  folders file  (Get-DnavConfigDir)\folders'
}

Initialize-DnavConfig
