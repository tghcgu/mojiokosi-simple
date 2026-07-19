$ErrorActionPreference = "Stop"

$workspace = Split-Path -Parent $PSScriptRoot
$startScript = Join-Path $PSScriptRoot "Start-LiveCaptionsToNotepad.ps1"
$targetPath = Join-Path $env:SystemRoot "System32\WindowsPowerShell\v1.0\powershell.exe"
$iconPath = Join-Path $env:SystemRoot "System32\shell32.dll"

$appName = -join ([char[]]@(
    0x6587, 0x5b57, 0x8d77, 0x3053, 0x3057
))
$legacyBaseName = -join ([char[]]@(
    0x30e9, 0x30a4, 0x30d6,
    0x30ad, 0x30e3, 0x30d7, 0x30b7, 0x30e7, 0x30f3,
    0x6587, 0x5b57, 0x8d77, 0x3053, 0x3057
))
$stopMode = -join ([char[]]@(0x505c, 0x6b62))
$shortcutName = "$appName.lnk"

$transcripts = Join-Path $workspace "transcripts"
if (-not (Test-Path -LiteralPath $transcripts)) {
    New-Item -ItemType Directory -Path $transcripts | Out-Null
}

try {
    (Get-Item -LiteralPath $PSScriptRoot).Attributes =
        (Get-Item -LiteralPath $PSScriptRoot).Attributes -bor [System.IO.FileAttributes]::Hidden
} catch {
}

$cleanupDirs = @(
    $workspace,
    [Environment]::GetFolderPath("Desktop"),
    [Environment]::GetFolderPath("Programs")
)

$taskbarDir = Join-Path $env:APPDATA "Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar"
if (Test-Path -LiteralPath $taskbarDir) {
    $cleanupDirs += $taskbarDir
}

$legacyShortcutNames = @(
    "$legacyBaseName.lnk",
    "$legacyBaseName$stopMode.lnk",
    "$legacyBaseName (2).lnk",
    "$legacyBaseName$stopMode (2).lnk"
)

foreach ($dir in $cleanupDirs) {
    foreach ($name in $legacyShortcutNames) {
        Remove-Item -LiteralPath (Join-Path $dir $name) -Force -ErrorAction SilentlyContinue
    }
}

$shell = New-Object -ComObject WScript.Shell

function New-AppShortcut {
    param(
        [string]$Directory,
        [string]$Name,
        [string]$Arguments,
        [string]$IconLocation,
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory | Out-Null
    }

    $shortcut = $script:shell.CreateShortcut((Join-Path $Directory $Name))
    $shortcut.TargetPath = $script:targetPath
    $shortcut.Arguments = $Arguments
    $shortcut.WorkingDirectory = $script:workspace
    $shortcut.IconLocation = $IconLocation
    $shortcut.WindowStyle = 7
    $shortcut.Description = $Description
    $shortcut.Save()
}

$startArgs = "-WindowStyle Hidden -STA -NoProfile -ExecutionPolicy Bypass -File `"$startScript`""
$desktop = [Environment]::GetFolderPath("Desktop")
New-AppShortcut `
    -Directory $desktop `
    -Name $shortcutName `
    -Arguments $startArgs `
    -IconLocation "$iconPath,168" `
    -Description "Desktop audio transcription"

Write-Host "The transcription shortcut was created on the Desktop."

