<#
Tests for the playlist scripts. Run from the repo root:
    powershell -NoProfile -ExecutionPolicy Bypass -File tests\run_tests.ps1
yt-dlp is replaced by tests\fake_ytdlp.ps1, so no network is used.
Exits 0 when every check passes.
#>
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot
$Fake = Join-Path $PSScriptRoot 'fake_ytdlp.ps1'
$Utf8 = New-Object System.Text.UTF8Encoding $false
$script:Failed = 0
$script:Passed = 0

function Check($name, [bool]$ok, $detail = '') {
    if ($ok) { $script:Passed++; Write-Host "  ok    $name" }
    else { $script:Failed++; Write-Host "  FAIL  $name  $detail" -ForegroundColor Red }
}

function New-Sandbox {
    $dir = Join-Path ([IO.Path]::GetTempPath()) ("ytdlp-test-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $dir | Out-Null
    $env:FAKE_YTDLP_LOG = Join-Path $dir 'calls.log'
    $env:FAKE_YTDLP_FIXTURE = Join-Path $dir 'fixture.txt'
    $env:FAKE_YTDLP_UNAVAILABLE = ''
    $env:FAKE_YTDLP_BREAK = ''
    [IO.File]::WriteAllText($env:FAKE_YTDLP_LOG, '', $Utf8)
    $dir
}

function Set-Fixture($folder, [string[]]$entries) {
    # entries: "id|title", in playlist order
    $lines = $entries | ForEach-Object { $id, $title = $_ -split '\|', 2; "$id`t$folder`t$title" }
    [IO.File]::WriteAllLines($env:FAKE_YTDLP_FIXTURE, [string[]]$lines, $Utf8)
}

function Touch($dir, [string[]]$names) {
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    foreach ($n in $names) { [IO.File]::WriteAllText((Join-Path $dir $n), 'x') }
}

function Entries($m3u) { @([IO.File]::ReadAllLines($m3u, $Utf8) | Where-Object { $_ -and -not $_.StartsWith('#') }) }

function Download($root, $url, $list) {
    $out = @(& (Join-Path $Repo 'download_playlist.ps1') -Url $url -Root $root -List $list -YtDlp $Fake *>&1 | ForEach-Object { "$_" })
    [pscustomobject]@{ Code = $LASTEXITCODE; Output = ($out -join "`n") }
}

$Url = 'https://www.youtube.com/playlist?list=PLtest123'

# --------------------------------------------------------------------------
Write-Host "syntax"
foreach ($f in Get-ChildItem $Repo -Recurse -Filter *.ps1) {
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors)
    Check "parses: $($f.Name)" ($errors.Count -eq 0) ($errors | Select-Object -First 1)
    # Windows PowerShell 5.1 reads BOM-less files as ANSI and garbles non-ASCII literals.
    $b = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = $b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF
    Check "ASCII-only or UTF-8 BOM: $($f.Name)" ($hasBom -or -not ($b | Where-Object { $_ -gt 127 } | Select-Object -First 1))
}

# --------------------------------------------------------------------------
Write-Host "make_playlists.ps1"
$sb = New-Sandbox
$pl = Join-Path $sb 'Mix'
Touch $pl @('10 - ten.m4a', '002 - two.opus', '1 - one.mp3', 'zeta.opus', 'cover.jpg', 'notes.txt',
    '003 - #1 Hits ♫ 100% Rock？.m4a')
& (Join-Path $Repo 'make_playlists.ps1') -Root $sb | Out-Null
$m3u = Join-Path $pl 'Mix.m3u'
$e = Entries $m3u
Check 'playlist written beside the songs' (Test-Path -LiteralPath $m3u)
Check 'numeric order, unnumbered last, non-audio skipped' (($e[0] -eq '1 - one.mp3') -and ($e[1] -eq '002 - two.opus') -and ($e[3] -eq '10 - ten.m4a') -and ($e[4] -eq 'zeta.opus') -and $e.Count -eq 5) ($e -join ' | ')
Check "'#' and '%' percent-encoded for VLC" ($e[2] -eq '003 - %231 Hits ♫ 100%25 Rock？.m4a') $e[2]
$bytes = [IO.File]::ReadAllBytes($m3u)
Check 'UTF-8 without BOM' (-not ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB))
Check 'LF line endings only' (-not ([IO.File]::ReadAllText($m3u).Contains("`r")))
$before = (Get-Item -LiteralPath $m3u).LastWriteTimeUtc
Start-Sleep -Milliseconds 1100
& (Join-Path $Repo 'make_playlists.ps1') -Root $sb | Out-Null
Check 'unchanged playlist is not rewritten' ((Get-Item -LiteralPath $m3u).LastWriteTimeUtc -eq $before)
Touch (Join-Path $sb 'Empty') @('readme.txt')
& (Join-Path $Repo 'make_playlists.ps1') -Root $sb | Out-Null
Check 'folder without audio gets no playlist' (-not (Test-Path (Join-Path $sb 'Empty\Empty.m3u')))
& (Join-Path $Repo 'make_playlists.ps1') -Root (Join-Path $sb 'missing') *>&1 | Out-Null
Check 'missing root exits 1' ($LASTEXITCODE -eq 1)
Remove-Item -Recurse -Force $sb

# --------------------------------------------------------------------------
Write-Host "download_playlist.ps1"
$sb = New-Sandbox; $root = Join-Path $sb 'music'; $list = Join-Path $sb 'playlists.txt'
[IO.File]::WriteAllText($list, '# links', $Utf8)   # no trailing newline, like a phone editor
Set-Fixture 'My Mix' @('aaa|Song A', 'bbb|Song B', 'ccc|Song C')
$r = Download $root $Url $list
$dir = Join-Path $root 'My Mix'
$names = @(Get-ChildItem -LiteralPath $dir -Filter *.m4a | Sort-Object Name | ForEach-Object Name)
Check 'first pull: all songs numbered from 001' (($names -join '|') -eq '001 - Song A.m4a|002 - Song B.m4a|003 - Song C.m4a') ($names -join '|')
Check 'first pull: archive logs every id' (@(Get-Content (Join-Path $root ".archive\PLtest123.txt")).Count -eq 3)
Check 'first pull: m3u lists 3 songs' ((Entries (Join-Path $dir 'My Mix.m3u')).Count -eq 3)
$listLines = [IO.File]::ReadAllLines($list)
Check 'playlist link added to list on its own line' (($listLines.Count -eq 2) -and ($listLines[1] -eq "https://www.youtube.com/playlist?list=PLtest123")) ($listLines -join ' | ')

$r = Download $root $Url $list
Check 'rerun with nothing new downloads nothing' (($r.Output -match "is up to date") -and -not (Select-String -LiteralPath $env:FAKE_YTDLP_LOG -Pattern '^-a ' | Select-Object -Skip 1)) $r.Output
Check 'link not added twice' ([IO.File]::ReadAllLines($list).Count -eq 2)

Set-Fixture 'My Mix' @('aaa|Song A', 'bbb|Song B', 'ccc|Song C', 'ddd|Song D', 'eee|Song E')
$r = Download $root $Url $list
$new = @(Get-ChildItem -LiteralPath $dir -Filter *.m4a | Sort-Object Name | Select-Object -Last 2 | ForEach-Object Name)
Check 'songs added at the bottom continue the numbering' (($new -join '|') -eq '004 - Song D.m4a|005 - Song E.m4a') ($new -join '|')
Check 'existing files are not renamed' (Test-Path -LiteralPath (Join-Path $dir '001 - Song A.m4a'))

Set-Fixture 'My Mix' @('ggg|Song G', 'fff|Song F', 'aaa|Song A', 'bbb|Song B', 'ccc|Song C', 'ddd|Song D', 'eee|Song E')
$r = Download $root $Url $list
Check 'songs added at the top: oldest new song gets the lower number' ((Test-Path -LiteralPath (Join-Path $dir '006 - Song F.m4a')) -and (Test-Path -LiteralPath (Join-Path $dir '007 - Song G.m4a')))

Set-Fixture 'My Mix' @('aaa|Song A', 'ccc|Song C', 'ddd|Song D', 'eee|Song E', 'fff|Song F', 'ggg|Song G')
$r = Download $root $Url $list
Check 'song removed from YouTube keeps its local copy' (Test-Path -LiteralPath (Join-Path $dir '002 - Song B.m4a'))
Check 'removed song stays in the m3u' ((Entries (Join-Path $dir 'My Mix.m3u')) -contains '002 - Song B.m4a')
Remove-Item -Recurse -Force $sb

$sb = New-Sandbox; $root = Join-Path $sb 'music'; $list = Join-Path $sb 'none.txt'
Touch (Join-Path $root 'Old Pull') @('0001 - Kept One.opus', '0002 - Kept Two.opus', '0003 - Phone Only.opus')
Set-Fixture 'Old Pull' @('k1|Kept One', 'n1|Brand New', 'k2|Kept Two')
$r = Download $root $Url $list
Check 'existing files matched by title are not downloaded again' ($r.Output -match 'Matched 2 song') $r.Output
Check 'matched ids are logged in the archive' ((Get-Content (Join-Path $root '.archive\PLtest123.txt')) -contains 'youtube k1')
Check 'new song follows the highest number with the same width' (Test-Path -LiteralPath (Join-Path $root 'Old Pull\0004 - Brand New.m4a'))
Check 'missing list file is not created' (-not (Test-Path $list))
Remove-Item -Recurse -Force $sb

$sb = New-Sandbox; $root = Join-Path $sb 'music'; $list = Join-Path $sb 'none.txt'
Set-Fixture 'Gaps' @('a1|One', 'd1|[Deleted video]', 'p1|[Private video]', 'u1|Gone', 'x1|Breaks', 'b1|Two')
$env:FAKE_YTDLP_UNAVAILABLE = 'u1'; $env:FAKE_YTDLP_BREAK = 'x1'
$r = Download $root $Url $list
$batch = (Select-String -LiteralPath $env:FAKE_YTDLP_LOG -Pattern '^batch: ').Line
$got = @(Get-ChildItem -LiteralPath (Join-Path $root 'Gaps') -File | ForEach-Object Name)
Check 'deleted and private placeholders are never requested' ($batch -eq 'batch: a1,u1,x1,b1') $batch
Check 'failures give a non-zero exit code' ($r.Code -ne 0) "code=$($r.Code)"
Check 'leftover .part files are cleaned up' (-not ($got | Where-Object { $_ -match '\.part' })) ($got -join '|')
Check 'songs around the failures still download' (($got -contains '001 - One.m4a') -and ($got -contains '003 - Two.m4a')) ($got -join '|')
Check 'failed songs stay out of the archive, so they are retried' (-not ((Get-Content (Join-Path $root '.archive\PLtest123.txt')) -match 'u1|x1'))
Remove-Item -Recurse -Force $sb

# --------------------------------------------------------------------------
Write-Host "update_all.ps1"
$sb = New-Sandbox; $root = Join-Path $sb 'music'; $list = Join-Path $sb 'sync\playlists.txt'
New-Item -ItemType Directory -Path (Split-Path $list) | Out-Null
[IO.File]::WriteAllText($list, "# links`n$Url`nhttps://evil.example/?list=PLx`nhttp://www.youtube.com/playlist?list=PLx`n", $Utf8)
Set-Fixture 'Auto' @('a1|One')
& (Join-Path $Repo 'update_all.ps1') -List $list -Root $root -YtDlp $Fake *>&1 | Out-Null
$summary = [IO.File]::ReadAllText((Join-Path $sb 'sync\last_run.txt'))
Check 'listed playlist is downloaded' (Test-Path -LiteralPath (Join-Path $root 'Auto\001 - One.m4a'))
Check 'non-YouTube and non-https links are skipped' ((([regex]::Matches($summary, 'Skipped, not a YouTube playlist link')).Count -eq 2) -and -not (Select-String -LiteralPath $env:FAKE_YTDLP_LOG -SimpleMatch 'evil.example' -Quiet)) $summary
Check 'summary written next to the list' ($summary -match "'Auto' is up to date|Downloading 1 new song") $summary
$calls = (Get-Content $env:FAKE_YTDLP_LOG).Count
& (Join-Path $Repo 'update_all.ps1') -List $list -Root $root -YtDlp $Fake *>&1 | Out-Null
Check 'unchanged list within a day: no yt-dlp calls' ((Get-Content $env:FAKE_YTDLP_LOG).Count -eq $calls)
[IO.File]::AppendAllText($list, "# edited on the phone`n", $Utf8)
& (Join-Path $Repo 'update_all.ps1') -List $list -Root $root -YtDlp $Fake *>&1 | Out-Null
Check 'edited list triggers a run' ((Get-Content $env:FAKE_YTDLP_LOG).Count -gt $calls)
Remove-Item -Recurse -Force $sb

Write-Host ""
Write-Host "$script:Passed passed, $script:Failed failed"
exit ([int]($script:Failed -gt 0))
