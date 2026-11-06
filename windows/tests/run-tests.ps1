# Tests for windows/FileConverter.psm1. Runs on any PowerShell 7 (Linux/macOS
# too) and Windows PowerShell 5.1:  pwsh windows/tests/run-tests.ps1
# Unit tests always run; conversion tests run when ffmpeg (and ImageMagick
# `magick`, or IM6 `convert`) are installed.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Import-Module (Join-Path $root 'FileConverter.psm1') -Force
$formats = Get-FcFormats -Path (Join-Path (Split-Path -Parent $root) 'shared/formats.json')
$script:failures = 0; $script:passes = 0

function Check([string]$Name, [scriptblock]$Test) {
    try {
        $ok = & $Test
        if ($ok -eq $false) { throw 'assertion returned false' }
        $script:passes++; Write-Host "  ok   $Name"
    } catch {
        $script:failures++; Write-Host "  FAIL $Name -> $($_.Exception.Message)" -ForegroundColor Red
    }
}
function Throws([scriptblock]$Block, [string]$Like) {
    try { & $Block; return $false } catch { return ($_.Exception.Message -like $Like) }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("fc-tests-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
$fakeTools = @{ ffmpeg = 'ffmpeg.exe'; magick = 'magick.exe'; soffice = $null }

Write-Host 'Formats & categories'
Check 'mov is video' { (Get-FcCategory -Formats $formats -Extension 'MOV') -eq 'video' }
Check 'jpeg normalizes to jpg image' { (Get-FcExtension -Path 'C:\a\B.JPEG') -eq 'jpg' -and (Get-FcCategory -Formats $formats -Extension 'jpg') -eq 'image' }
Check 'gif is animatedImage' { (Get-FcCategory -Formats $formats -Extension 'gif') -eq 'animatedImage' }
Check 'unknown extension has no category' { $null -eq (Get-FcCategory -Formats $formats -Extension 'xyz') }
Check 'video targets include mp4, gif, mp3; not jpg' {
    $t = @(Get-FcTargets -Formats $formats -Category 'video' | ForEach-Object { $_.Ext })
    ($t -contains 'mp4') -and ($t -contains 'gif') -and ($t -contains 'mp3') -and -not ($t -contains 'jpg')
}
Check 'image targets include jpg, png, webp, ico, pdf, gif' {
    $t = @(Get-FcTargets -Formats $formats -Category 'image' | ForEach-Object { $_.Ext })
    @('jpg', 'png', 'webp', 'ico', 'pdf', 'gif') | ForEach-Object { if ($t -notcontains $_) { throw "missing $_" } }
    -not ($t -contains 'mp4')
}
Check 'ogv is offered on desktop (web-only restriction ignored)' { @(Get-FcTargets -Formats $formats -Category 'video' | ForEach-Object { $_.Ext }) -contains 'ogv' }

Write-Host 'Paths'
Check 'output path swaps extension next to input' {
    $p = Get-FcOutputPath -InputPath (Join-Path $tmp 'clip.mov') -To 'MP4'
    $p -eq (Join-Path $tmp 'clip.mp4')
}
Check 'unique path appends (1), (2)' {
    $a = Join-Path $tmp 'taken.mp4'; Set-Content $a 'x'; Set-Content (Join-Path $tmp 'taken (1).mp4') 'x'
    (Get-FcUniquePath -Path $a) -eq (Join-Path $tmp 'taken (2).mp4')
}

Write-Host 'Plans'
$in = Join-Path $tmp 'my clip.mov'
Check 'mp4 plan uses shared ffmpeg args' {
    $plan = Get-FcPlan -Formats $formats -InputPath $in -To mp4 -Tools $fakeTools -OutputPath 'out.mp4'
    $a = @($plan.Steps[0].Args)
    ($plan.Steps.Count -eq 1) -and ($a -contains 'libx264') -and ($a[[array]::IndexOf($a, '-crf') + 1] -eq '23') -and ($a[-1] -eq 'out.mp4') -and ($a -contains $in) -and ($a -contains '-n')
}
Check 'webm on desktop is VP9 (webFfmpeg is browser-only)' {
    $plan = Get-FcPlan -Formats $formats -InputPath $in -To webm -Tools $fakeTools -OutputPath 'o.webm'
    @($plan.Steps[0].Args) -contains 'libvpx-vp9'
}
Check 'gif plan is two passes with a temp palette' {
    $plan = Get-FcPlan -Formats $formats -InputPath $in -To gif -Tools $fakeTools -OutputPath 'o.gif' -TempDir $tmp
    ($plan.Steps.Count -eq 2) -and (@($plan.TempFiles).Count -eq 1) -and (@($plan.Steps[1].Args) -contains 'fps=15,paletteuse')
}
Check 'image plan uses magick, first frame, quality' {
    $plan = Get-FcPlan -Formats $formats -InputPath 'C:\p\shot.png' -To jpg -Tools $fakeTools -OutputPath 'o.jpg'
    $a = @($plan.Steps[0].Args)
    ($plan.Steps[0].Exe -eq 'magick.exe') -and ($a[0] -eq 'C:\p\shot.png[0]') -and ($a -contains '-flatten') -and ($a[[array]::IndexOf($a, '-quality') + 1] -eq '90')
}
Check 'ico plan clamps to 256 and builds multi-size icon' {
    $a = @((Get-FcPlan -Formats $formats -InputPath 'a.png' -To ico -Tools $fakeTools -OutputPath 'o.ico').Steps[0].Args)
    ($a -contains '256x256>') -and ($a -contains 'icon:auto-resize=256,128,64,48,32,16')
}
Check 'still image -> gif goes through magick' { (Get-FcPlan -Formats $formats -InputPath 'a.png' -To gif -Tools $fakeTools -OutputPath 'o.gif').Steps[0].Exe -eq 'magick.exe' }
Check 'mp3 -> jpg is rejected' { Throws { Get-FcPlan -Formats $formats -InputPath 'a.mp3' -To jpg -Tools $fakeTools } "Can't convert .mp3 to JPG*" }
Check 'docx -> pdf needs LibreOffice' { Throws { Get-FcPlan -Formats $formats -InputPath 'a.docx' -To pdf -Tools $fakeTools } '*LibreOffice*' }
Check 'docx -> pdf with LibreOffice renames soffice output' {
    $plan = Get-FcPlan -Formats $formats -InputPath 'C:\d\Report.docx' -To pdf -Tools @{ ffmpeg = 'f'; magick = 'm'; soffice = 'soffice.exe' } -OutputPath 'C:\d\Report.pdf' -TempDir $tmp
    ($plan.Steps[0].Exe -eq 'soffice.exe') -and ($plan.RenameFrom -like '*Report.pdf') -and (@($plan.Steps[0].Args) -contains '--convert-to')
}
Check 'missing ffmpeg gives an actionable error' { Throws { Get-FcPlan -Formats $formats -InputPath 'a.mov' -To mp4 -Tools @{ ffmpeg = $null; magick = 'm' } } '*ffmpeg is missing*' }

Write-Host 'Command-line quoting'
Check 'plain arg unquoted' { (ConvertTo-FcArgument -Value 'abc') -eq 'abc' }
Check 'spaces quoted' { (ConvertTo-FcArgument -Value 'C:\My Files\a b.mov') -eq '"C:\My Files\a b.mov"' }
Check 'embedded quote escaped' { (ConvertTo-FcArgument -Value 'say "hi"') -eq '"say \"hi\""' }
Check 'trailing backslash doubled inside quotes' { (ConvertTo-FcArgument -Value 'C:\a b\') -eq '"C:\a b\\"' }
Check 'empty string quoted' { (ConvertTo-FcArgument -Value '') -eq '""' }

Write-Host 'Right-click menu layout'
$entries = Get-FcMenuEntries -Formats $formats -ScriptPath 'C:\Users\u\AppData\Local\FileConverter\fc-convert.ps1' -IconPath 'C:\x\FileConverter.ico'
Check '.mp4 gets the video submenu' {
    $e = $entries | Where-Object { $_.Key -eq 'Software\Classes\SystemFileAssociations\.mp4\shell\FileConverter' }
    ($e.Values.ExtendedSubCommandsKey -eq 'FileConverter.video') -and ($e.Values.MUIVerb -eq 'Convert with File Converter') -and ($e.Values.Icon -like '*.ico')
}
Check '.jpg gets the image submenu, .gif the animated one' {
    ($entries | Where-Object { $_.Key -like '*\.jpg\shell\FileConverter' }).Values.ExtendedSubCommandsKey -eq 'FileConverter.image' -and
    ($entries | Where-Object { $_.Key -like '*\.gif\shell\FileConverter' }).Values.ExtendedSubCommandsKey -eq 'FileConverter.animatedImage'
}
Check 'video submenu commands pass -To and "%1"' {
    $cmd = $entries | Where-Object { $_.Key -like 'Software\Classes\FileConverter.video\shell\*mp4\command' }
    $cmd.Values['(default)'] -match '-File "C:\\Users\\u\\AppData\\Local\\FileConverter\\fc-convert.ps1" -To mp4 "%1"$'
}
Check 'submenu items are ordered and labelled' {
    $labels = @($entries | Where-Object { $_.Key -match '^Software\\Classes\\FileConverter\.audio\\shell\\\d\d\w+$' } | ForEach-Object { $_.Values.MUIVerb })
    ($labels -join ',') -eq 'FLAC,MP3,OGG,WAV,AAC' -or ($labels.Count -ge 5)
}
Check 'no Office menu without LibreOffice; added with -IncludeOffice' {
    $none = @($entries | Where-Object { $_.Key -like '*\.docx\*' }).Count -eq 0
    $with = Get-FcMenuEntries -Formats $formats -ScriptPath 's.ps1' -IncludeOffice
    $none -and (($with | Where-Object { $_.Key -like '*\.docx\shell\FileConverter' }).Values.ExtendedSubCommandsKey -eq 'FileConverter.office')
}
Check 'uninstall roots cover every menu key' {
    $roots = Get-FcMenuRoots -Formats $formats
    $all = Get-FcMenuEntries -Formats $formats -ScriptPath 's.ps1' -IncludeOffice
    @($all | Where-Object { $k = $_.Key; -not ($roots | Where-Object { $k -eq $_ -or $k.StartsWith($_ + '\') }) }).Count -eq 0
}

# --- real conversions ------------------------------------------------------
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue | Select-Object -First 1)
$magick = (Get-Command magick -ErrorAction SilentlyContinue | Select-Object -First 1)
if (-not $magick) { $magick = (Get-Command convert -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1) }  # IM6 takes the same arguments
$ffprobe = (Get-Command ffprobe -ErrorAction SilentlyContinue | Select-Object -First 1)
if ($ffmpeg -and $ffprobe) {
    Write-Host 'Real conversions'
    $tools = @{ ffmpeg = $ffmpeg.Source; magick = $(if ($magick) { $magick.Source } else { $null }); soffice = $null }
    $clip = Join-Path $tmp 'sample clip.mov'
    & $ffmpeg.Source -v error -y -f lavfi -i 'testsrc=duration=1:size=160x120:rate=10' -f lavfi -i 'sine=frequency=440:duration=1' -c:v libx264 -preset ultrafast -c:a aac -shortest $clip
    function Probe($f) { (& $ffprobe.Source -v error -show_entries stream=codec_name -of csv=p=0 $f) -join ',' }
    foreach ($case in @(@('mp4', 'h264,aac'), @('webm', 'vp9,vorbis'), @('gif', 'gif'), @('mp3', 'mp3'), @('wav', 'pcm_s16le'))) {
        $to = $case[0]; $want = $case[1]
        Check "mov -> $to" {
            $out = Invoke-FcPlan -Plan (Get-FcPlan -Formats $formats -InputPath $clip -To $to -Tools $tools -TempDir $tmp)
            ((Probe $out) -eq $want) -and ([IO.Path]::GetFileName($out) -eq "sample clip.$to")
        }
    }
    Check 'second mp4 conversion does not overwrite: "sample clip (1).mp4"' {
        $out = Invoke-FcPlan -Plan (Get-FcPlan -Formats $formats -InputPath $clip -To mp4 -Tools $tools)
        [IO.Path]::GetFileName($out) -eq 'sample clip (1).mp4'
    }
    Check 'no palette temp files left behind' { @(Get-ChildItem $tmp -Filter 'fc-palette-*').Count -eq 0 }
    Check 'failed conversion removes partial output and reports the tool error' {
        $bad = Join-Path $tmp 'broken.mp4'; Set-Content $bad 'not a video'
        $plan = Get-FcPlan -Formats $formats -InputPath $bad -To webm -Tools $tools
        (Throws { Invoke-FcPlan -Plan $plan } 'ffmpeg* failed*') -and -not (Test-Path $plan.Output)
    }
    if ($magick) {
        $png = Join-Path $tmp 'shot.png'
        & $ffmpeg.Source -v error -y -f lavfi -i 'color=c=red:s=300x200' -frames:v 1 $png
        foreach ($case in @(@('jpg', '^mjpeg'), @('webp', '^webp'))) {
            $to = $case[0]; $want = $case[1]
            Check "png -> $to" { (Probe (Invoke-FcPlan -Plan (Get-FcPlan -Formats $formats -InputPath $png -To $to -Tools $tools))) -match $want }
        }
        # ICO entries are PNG or BMP depending on ImageMagick version/size; both are valid.
        Check 'png -> ico (multi-size)' {
            $codecs = @((Probe (Invoke-FcPlan -Plan (Get-FcPlan -Formats $formats -InputPath $png -To ico -Tools $tools))) -split ',' | Where-Object { $_ })
            ($codecs.Count -ge 2) -and (@($codecs | Where-Object { $_ -notmatch '^(png|bmp)$' }).Count -eq 0)
        }
    }
    Check 'fc-convert.ps1 end to end (-Quiet)' {
        $script = Join-Path $root 'fc-convert.ps1'
        $stage = Join-Path $tmp 'stage'; New-Item -ItemType Directory $stage | Out-Null
        Copy-Item $script, (Join-Path $root 'FileConverter.psm1') $stage
        Copy-Item (Join-Path (Split-Path -Parent $root) 'shared/formats.json') $stage
        $tools | ConvertTo-Json | Set-Content (Join-Path $stage 'tools.json')
        $exe = (Get-Process -Id $PID).Path
        & $exe -NoProfile -File (Join-Path $stage 'fc-convert.ps1') -To mp3 $clip -Quiet
        ($LASTEXITCODE -eq 0) -and (Test-Path (Join-Path $tmp 'sample clip (1).mp3'))
    }
} else {
    Write-Host 'Real conversions: skipped (ffmpeg/ffprobe not installed)'
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
Write-Host ("{0} passed, {1} failed" -f $script:passes, $script:failures)
if ($script:failures) { exit 1 }
