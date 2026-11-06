<#
.SYNOPSIS
  Converts files with File Converter. Called by the Explorer right-click
  menu ("Convert with File Converter" > MP4 / MP3 / JPG ...), one call per
  selected file:  fc-convert.ps1 -To mp4 "C:\path\clip.mov"
.DESCRIPTION
  Writes the result next to the original ("clip.mp4", or "clip (1).mp4" if
  taken). The original is never changed. Shows a notification when done
  and a message box with the tool's error text if it fails.
#>
param(
    [Parameter(Mandatory = $true)][string]$To,
    [Parameter(Mandatory = $true, ValueFromRemainingArguments = $true)][string[]]$Path,
    [switch]$Quiet
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
Import-Module (Join-Path $here 'FileConverter.psm1') -Force
$formats = Get-FcFormats -Path (Join-Path $here 'formats.json')

# tools.json is written by install.ps1; fall back to searching.
$tools = Find-FcTools
$toolsFile = Join-Path $here 'tools.json'
if (Test-Path -LiteralPath $toolsFile) {
    $saved = Get-Content -LiteralPath $toolsFile -Raw | ConvertFrom-Json
    foreach ($name in @('ffmpeg', 'magick', 'soffice')) {
        $p = $saved.PSObject.Properties[$name]
        if ($p -and $p.Value -and (Test-Path -LiteralPath $p.Value)) { $tools[$name] = $p.Value }
    }
}

# Windows UI (toast / balloon / message box). Kept as text and compiled only
# on Windows: PowerShell resolves type literals such as WinRT and WinForms
# types when it compiles a function body, which fails elsewhere.
$script:WindowsNotice = @'
param($Title, $Text, $IsError)
if ($IsError) {
    Add-Type -AssemblyName System.Windows.Forms
    [void][System.Windows.Forms.MessageBox]::Show($Text, $Title, 'OK', 'Error')
    return
}
try {
    [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
    $xml = [Windows.UI.Notifications.ToastNotificationManager]::GetTemplateContent([Windows.UI.Notifications.ToastTemplateType]::ToastText02)
    $texts = $xml.GetElementsByTagName('text')
    [void]$texts.Item(0).AppendChild($xml.CreateTextNode($Title))
    [void]$texts.Item(1).AppendChild($xml.CreateTextNode($Text))
    $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
    [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
} catch {
    # Older Windows / no WinRT: a tray balloon instead.
    Add-Type -AssemblyName System.Windows.Forms, System.Drawing
    $icon = New-Object System.Windows.Forms.NotifyIcon
    $icon.Icon = [System.Drawing.SystemIcons]::Information
    $icon.Visible = $true
    $icon.ShowBalloonTip(5000, $Title, $Text, 'Info')
    Start-Sleep -Seconds 5
    $icon.Dispose()
}
'@

function Show-FcNotice {
    param([string]$Title, [string]$Text, [switch]$IsError)
    if ($Quiet) { return }
    if ($env:OS -ne 'Windows_NT') { Write-Host "$Title - $Text"; return }
    & ([scriptblock]::Create($script:WindowsNotice)) $Title $Text ([bool]$IsError)
}

$done = @(); $failed = @()
foreach ($file in $Path) {
    try {
        $plan = Get-FcPlan -Formats $formats -InputPath $file -To $To -Tools $tools
        $done += Invoke-FcPlan -Plan $plan
    } catch {
        $failed += ("{0}: {1}" -f [IO.Path]::GetFileName($file), $_.Exception.Message)
    }
}

if ($done.Count) {
    $names = ($done | ForEach-Object { [IO.Path]::GetFileName($_) }) -join ', '
    Show-FcNotice -Title 'File Converter' -Text ("Converted to {0}: {1}" -f $To.ToUpperInvariant(), $names)
}
if ($failed.Count) {
    Show-FcNotice -Title 'File Converter - conversion failed' -Text ($failed -join "`n`n") -IsError
    exit 1
}
