# File Converter for Windows - core logic.
#
# Pure functions (format lookup, conversion plans, right-click menu layout)
# kept separate from the side effects in fc-convert.ps1 / install.ps1 so
# they can be unit-tested anywhere PowerShell runs (windows/tests).
#
# Compatible with Windows PowerShell 5.1 (the one every Windows ships with)
# and PowerShell 7+. Formats come from shared/formats.json - the same
# table the web converter, the browser extension and the macOS app use.

Set-StrictMode -Version 2.0

$script:MenuVerb = 'FileConverter'
$script:MenuTitle = 'Convert with File Converter'
$script:OfficeExtensions = @('doc', 'docx', 'odt', 'xls', 'xlsx', 'ods', 'ppt', 'pptx', 'odp')
# Image formats ImageMagick reads only with extra delegates (Ghostscript for
# PDF, LibreOffice for Office) aren't offered as image sources.
$script:ImageInputsNeedingDelegates = @('pdf', 'svg')

function Get-FcFormats {
    param([Parameter(Mandatory)][string]$Path)
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Get-FcExtension {
    param([Parameter(Mandatory)][string]$Path)
    $ext = [IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
    if ($ext -eq 'jpeg') { 'jpg' } else { $ext }
}

function Get-FcCategory {
    param([Parameter(Mandatory)]$Formats, [Parameter(Mandatory)][string]$Extension)
    $ext = $Extension.TrimStart('.').ToLowerInvariant()
    foreach ($prop in $Formats.categories.PSObject.Properties) {
        if (@($prop.Value) -contains $ext) { return $prop.Name }
        if ($ext -eq 'jpg' -and @($prop.Value) -contains 'jpeg') { return $prop.Name }
    }
    return $null
}

function Get-FcOutput {
    param([Parameter(Mandatory)]$Formats, [Parameter(Mandatory)][string]$To)
    $prop = $Formats.outputs.PSObject.Properties[$To.ToLowerInvariant()]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

<#
  Target formats offered for a category on Windows, in table order.
  Documents: only Office -> PDF (needs LibreOffice), handled separately.
#>
function Get-FcTargets {
    param([Parameter(Mandatory)]$Formats, [Parameter(Mandatory)][string]$Category)
    $targets = @()
    if ($Category -eq 'document') { return $targets }
    foreach ($prop in $Formats.outputs.PSObject.Properties) {
        $o = $prop.Value
        if (@($o.accepts) -notcontains $Category) { continue }
        if ($prop.Name -eq 'pdf' -and $Category -ne 'image') { continue }
        $targets += [pscustomobject]@{ Ext = $prop.Name; Label = $o.label }
    }
    return $targets
}

<# "clip.mp4" taken -> "clip (1).mp4", same rule as UniquePath.swift. #>
function Get-FcUniquePath {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $Path }
    $dir = [IO.Path]::GetDirectoryName($Path)
    $stem = [IO.Path]::GetFileNameWithoutExtension($Path)
    $ext = [IO.Path]::GetExtension($Path)
    $i = 1
    while ($true) {
        $candidate = Join-Path $dir ("{0} ({1}){2}" -f $stem, $i, $ext)
        if (-not (Test-Path -LiteralPath $candidate)) { return $candidate }
        $i++
    }
}

function Get-FcOutputPath {
    param([Parameter(Mandatory)][string]$InputPath, [Parameter(Mandatory)][string]$To)
    $dir = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($InputPath))
    $stem = [IO.Path]::GetFileNameWithoutExtension($InputPath)
    Get-FcUniquePath -Path (Join-Path $dir ("{0}.{1}" -f $stem, $To.ToLowerInvariant()))
}

<#
  Builds the command(s) that convert $InputPath to $To, as data:
  @{ Steps = @(@{ Exe; Args }); Output; TempFiles; RenameFrom }
  $Tools: @{ ffmpeg = path; magick = path; soffice = path-or-$null }.
  Throws a readable error for unsupported combinations.
#>
function Get-FcPlan {
    param(
        [Parameter(Mandatory)]$Formats,
        [Parameter(Mandatory)][string]$InputPath,
        [Parameter(Mandatory)][string]$To,
        [Parameter(Mandatory)][hashtable]$Tools,
        [string]$OutputPath,
        [string]$TempDir = [IO.Path]::GetTempPath()
    )
    $to = $To.ToLowerInvariant()
    $spec = Get-FcOutput -Formats $Formats -To $to
    if ($null -eq $spec) { throw "Unknown format: $To" }
    $inExt = Get-FcExtension -Path $InputPath
    $category = Get-FcCategory -Formats $Formats -Extension $inExt
    if (-not $OutputPath) { $OutputPath = Get-FcOutputPath -InputPath $InputPath -To $to }

    # Office -> PDF through LibreOffice (writes <stem>.pdf into the out dir).
    if ($script:OfficeExtensions -contains $inExt) {
        if ($to -ne 'pdf') { throw "Office documents can only be converted to PDF." }
        if (-not $Tools['soffice']) { throw "Converting Office documents needs LibreOffice (https://www.libreoffice.org)." }
        $outDir = Join-Path $TempDir ("fc-" + [guid]::NewGuid().ToString('N'))
        $produced = Join-Path $outDir ([IO.Path]::GetFileNameWithoutExtension($InputPath) + '.pdf')
        return @{
            Steps      = @(@{ Exe = $Tools['soffice']; Args = @('--headless', '--convert-to', 'pdf', '--outdir', $outDir, $InputPath) })
            Output     = $OutputPath
            RenameFrom = $produced
            TempFiles  = @($outDir)
        }
    }

    if ($null -eq $category -or @($spec.accepts) -notcontains $category) {
        throw ("Can't convert .{0} to {1}." -f $inExt, $spec.label)
    }

    $isStill = ($category -eq 'image')
    $useMagick = ($null -ne $spec.PSObject.Properties['image']) -or ($to -eq 'gif' -and $isStill)
    if ($useMagick) {
        if ($script:ImageInputsNeedingDelegates -contains $inExt) { throw "Converting .$inExt images isn't supported on Windows yet." }
        if (-not $Tools['magick']) { throw "ImageMagick is missing - re-run the File Converter installer." }
        $magickArgs = @()
        if ($to -eq 'pdf') {
            $magickArgs += $InputPath
        } else {
            $magickArgs += ($InputPath + '[0]')   # first frame/page of GIF, TIFF, PSD...
        }
        if ($to -eq 'jpg') { $magickArgs += @('-background', 'white', '-flatten') }
        if ($null -ne $spec.PSObject.Properties['image']) {
            $img = $spec.image
            if ($null -ne $img.PSObject.Properties['maxSize'] -and $img.maxSize) {
                $magickArgs += @('-resize', ("{0}x{0}>" -f $img.maxSize))
            }
            if ($to -eq 'ico') { $magickArgs += @('-define', 'icon:auto-resize=256,128,64,48,32,16') }
            $magickArgs += @('-quality', [string]$img.quality)
        }
        $magickArgs += $OutputPath
        return @{ Steps = @(@{ Exe = $Tools['magick']; Args = $magickArgs }); Output = $OutputPath; TempFiles = @() }
    }

    if (-not $Tools['ffmpeg']) { throw "ffmpeg is missing - re-run the File Converter installer." }
    $base = @('-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-i', $InputPath)
    if ($null -ne $spec.PSObject.Properties['gif']) {
        $palette = Join-Path $TempDir ("fc-palette-" + [guid]::NewGuid().ToString('N') + '.png')
        $filter = "fps=$($spec.gif.fps)"
        return @{
            Steps = @(
                @{ Exe = $Tools['ffmpeg']; Args = ($base + @('-vf', "$filter,palettegen", $palette)) },
                @{ Exe = $Tools['ffmpeg']; Args = (@('-hide_banner', '-loglevel', 'error', '-nostdin', '-n', '-i', $InputPath, '-i', $palette, '-lavfi', "$filter,paletteuse", $OutputPath)) }
            )
            Output    = $OutputPath
            TempFiles = @($palette)
        }
    }
    return @{
        Steps     = @(@{ Exe = $Tools['ffmpeg']; Args = ($base + @($spec.ffmpeg) + @($OutputPath)) })
        Output    = $OutputPath
        TempFiles = @()
    }
}

<# Quotes one argument for a Windows command line (CommandLineToArgvW rules). #>
function ConvertTo-FcArgument {
    param([AllowEmptyString()][string]$Value)
    if ($Value -ne '' -and $Value -notmatch '[\s"]') { return $Value }
    $escaped = [regex]::Replace($Value, '(\\*)"', { param($m) ($m.Groups[1].Value * 2) + '\"' })
    $escaped = [regex]::Replace($escaped, '(\\+)$', { param($m) $m.Groups[1].Value * 2 })
    return '"' + $escaped + '"'
}

<#
  Runs a plan. Returns the output path; throws with the tool's error text.
#>
function Invoke-FcPlan {
    param([Parameter(Mandatory)][hashtable]$Plan)
    try {
        foreach ($step in $Plan.Steps) {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $step.Exe
            $psi.Arguments = (@($step.Args) | ForEach-Object { ConvertTo-FcArgument -Value ([string]$_) }) -join ' '
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true
            $psi.RedirectStandardError = $true
            $psi.RedirectStandardOutput = $true
            $proc = [System.Diagnostics.Process]::Start($psi)
            $stdoutTask = $proc.StandardOutput.ReadToEndAsync()
            $stderr = $proc.StandardError.ReadToEnd()
            $proc.WaitForExit()
            [void]$stdoutTask.Result
            if ($proc.ExitCode -ne 0) {
                $tail = ($stderr -split "`r?`n" | Where-Object { $_ } | Select-Object -Last 6) -join "`n"
                throw ("{0} failed ({1}): {2}" -f [IO.Path]::GetFileName($step.Exe), $proc.ExitCode, $tail)
            }
        }
        if ($Plan.ContainsKey('RenameFrom') -and $Plan.RenameFrom) {
            if (-not (Test-Path -LiteralPath $Plan.RenameFrom)) { throw "Converter produced no output." }
            Move-Item -LiteralPath $Plan.RenameFrom -Destination $Plan.Output
        }
        if (-not (Test-Path -LiteralPath $Plan.Output)) { throw "Converter produced no output." }
        return $Plan.Output
    } catch {
        if (Test-Path -LiteralPath $Plan.Output) { Remove-Item -LiteralPath $Plan.Output -Force -ErrorAction SilentlyContinue }
        throw
    } finally {
        foreach ($t in @($Plan.TempFiles)) {
            if ($t -and (Test-Path -LiteralPath $t)) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
}

<#
  The registry layout for the right-click menu, as data (no side effects):
  a list of @{ Key = 'Software\Classes\...'; Values = @{ name = value } }
  under HKEY_CURRENT_USER (no admin rights needed).

  Every supported extension gets
    SystemFileAssociations\.<ext>\shell\FileConverter
      MUIVerb = "Convert with File Converter", ExtendedSubCommandsKey = FileConverter.<category>
  and each category's submenu lives in
    FileConverter.<category>\shell\<NN><ext>\command = powershell ... -To <ext> "%1"
#>
function Get-FcMenuEntries {
    param(
        [Parameter(Mandatory)]$Formats,
        [Parameter(Mandatory)][string]$ScriptPath,
        [string]$IconPath,
        [switch]$IncludeOffice,
        [string]$PowerShellExe = 'powershell.exe'
    )
    $entries = New-Object System.Collections.ArrayList
    $runner = '{0} -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}"' -f $PowerShellExe, $ScriptPath

    $menus = [ordered]@{}
    foreach ($cat in @('video', 'audio', 'image', 'animatedImage')) {
        $menus[$cat] = @(Get-FcTargets -Formats $Formats -Category $cat)
    }
    if ($IncludeOffice) { $menus['office'] = @([pscustomobject]@{ Ext = 'pdf'; Label = 'PDF' }) }

    foreach ($cat in $menus.Keys) {
        $root = "Software\Classes\$($script:MenuVerb).$cat"
        $i = 0
        foreach ($target in $menus[$cat]) {
            $i++
            $verbKey = "$root\shell\{0:D2}{1}" -f $i, $target.Ext
            [void]$entries.Add(@{ Key = $verbKey; Values = @{ MUIVerb = $target.Label } })
            [void]$entries.Add(@{ Key = "$verbKey\command"; Values = @{ '(default)' = ('{0} -To {1} "%1"' -f $runner, $target.Ext) } })
        }
    }

    $extsByMenu = [ordered]@{}
    foreach ($cat in @('video', 'audio', 'image', 'animatedImage')) {
        $exts = @($Formats.categories.$cat | Where-Object { $script:ImageInputsNeedingDelegates -notcontains $_ -and $_ -ne 'cda' })
        $extsByMenu[$cat] = $exts
    }
    if ($IncludeOffice) { $extsByMenu['office'] = $script:OfficeExtensions }

    foreach ($cat in $extsByMenu.Keys) {
        foreach ($ext in $extsByMenu[$cat]) {
            $values = @{
                MUIVerb                = $script:MenuTitle
                ExtendedSubCommandsKey = "$($script:MenuVerb).$cat"
                MultiSelectModel       = 'Player'
            }
            if ($IconPath) { $values['Icon'] = $IconPath }
            [void]$entries.Add(@{ Key = "Software\Classes\SystemFileAssociations\.$ext\shell\$($script:MenuVerb)"; Values = $values })
        }
    }
    return , $entries
}

<# Keys to delete on uninstall / before re-install. #>
function Get-FcMenuRoots {
    param([Parameter(Mandatory)]$Formats)
    $roots = @()
    foreach ($cat in @('video', 'audio', 'image', 'animatedImage', 'office')) { $roots += "Software\Classes\$($script:MenuVerb).$cat" }
    $all = @()
    foreach ($prop in $Formats.categories.PSObject.Properties) { $all += @($prop.Value) }
    foreach ($ext in ($all + $script:OfficeExtensions | Sort-Object -Unique)) {
        $roots += "Software\Classes\SystemFileAssociations\.$ext\shell\$($script:MenuVerb)"
    }
    return $roots
}

<#
  Finds ffmpeg / magick / soffice: PATH first, then the places winget and the
  official installers use (Explorer's environment may predate the install,
  so PATH alone isn't enough right after installing).
#>
function Find-FcTools {
    $found = @{ ffmpeg = $null; magick = $null; soffice = $null }
    $names = @{ ffmpeg = @('ffmpeg.exe', 'ffmpeg'); magick = @('magick.exe', 'magick'); soffice = @('soffice.exe', 'soffice') }
    foreach ($tool in @('ffmpeg', 'magick', 'soffice')) {
        foreach ($n in $names[$tool]) {
            $cmd = Get-Command $n -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($cmd) { $found[$tool] = $cmd.Source; break }
        }
    }
    $candidates = @()
    if ($env:LOCALAPPDATA) {
        $candidates += @{ Tool = 'ffmpeg'; Glob = (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\ffmpeg.exe') }
        $candidates += @{ Tool = 'ffmpeg'; Glob = (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages\Gyan.FFmpeg*\*\bin\ffmpeg.exe') }
        $candidates += @{ Tool = 'magick'; Glob = (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\magick.exe') }
    }
    foreach ($pf in @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { $_ }) {
        $candidates += @{ Tool = 'magick'; Glob = (Join-Path $pf 'ImageMagick-*\magick.exe') }
        $candidates += @{ Tool = 'ffmpeg'; Glob = (Join-Path $pf 'ffmpeg\bin\ffmpeg.exe') }
        $candidates += @{ Tool = 'soffice'; Glob = (Join-Path $pf 'LibreOffice\program\soffice.exe') }
    }
    foreach ($c in $candidates) {
        if ($found[$c.Tool]) { continue }
        $hit = Get-ChildItem -Path $c.Glob -ErrorAction SilentlyContinue | Sort-Object FullName -Descending | Select-Object -First 1
        if ($hit) { $found[$c.Tool] = $hit.FullName }
    }
    return $found
}

Export-ModuleMember -Function Find-FcTools, Get-FcFormats, Get-FcExtension, Get-FcCategory, Get-FcOutput, Get-FcTargets, Get-FcUniquePath,
    Get-FcOutputPath, Get-FcPlan, ConvertTo-FcArgument, Invoke-FcPlan, Get-FcMenuEntries, Get-FcMenuRoots
