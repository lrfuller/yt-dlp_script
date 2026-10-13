# Stand-in for yt-dlp in tests. Handles the three calls download_playlist.ps1 makes:
#   single:   <url with v=> -P <root> -o <template> ...
#   listing:  <url> --flat-playlist ... --print-to-file <template> <file> ...
#   download: -a <batch> -P <root> -o <template> --autonumber-start <n> --download-archive <file> ...
# The playlist comes from $env:FAKE_YTDLP_FIXTURE: "id<TAB>folder<TAB>title[<TAB>list id]" per
# line; an entry with a list id is only listed for URLs with that list=.
# A listing of a list id in $env:FAKE_YTDLP_THROW throws, like an unexpected crash.
# IDs in $env:FAKE_YTDLP_UNAVAILABLE fail like a removed video (no number used).
# IDs in $env:FAKE_YTDLP_BREAK fail mid-download: a number is used and a .part file is left.
# Every call is appended to $env:FAKE_YTDLP_LOG.

function Arg($name) { $i = [array]::IndexOf($args_, $name); if ($i -ge 0) { $args_[$i + 1] } }
$args_ = $args
$utf8 = New-Object System.Text.UTF8Encoding $false
[IO.File]::AppendAllText($env:FAKE_YTDLP_LOG, (($args -join ' ') + "`n"), $utf8)

$fixture = @(foreach ($l in [IO.File]::ReadAllLines($env:FAKE_YTDLP_FIXTURE, $utf8)) {
    $id, $folder, $title, $list = $l -split "`t"
    [pscustomobject]@{ Id = $id; Folder = $folder; Title = $title; List = $list }
})
$unavailable = @("$env:FAKE_YTDLP_UNAVAILABLE" -split ',' | Where-Object { $_ })
$broken = @("$env:FAKE_YTDLP_BREAK" -split ',' | Where-Object { $_ })

if ($args -contains '--flat-playlist') {
    $listId = if ($args[0] -match '[?&]list=([\w-]+)') { $Matches[1] } else { '' }
    if ($listId -and ("$env:FAKE_YTDLP_THROW" -split ',') -contains $listId) { throw "fake crash listing $listId" }
    $i = [array]::IndexOf($args, '--print-to-file')
    $out = $args[$i + 2]
    $text = ($fixture | Where-Object { -not $_.List -or $_.List -eq $listId } |
        ForEach-Object { "$($_.Id)`t$($_.Folder)\$($_.Title)`n" }) -join ''
    [IO.File]::AppendAllText($out, $text, $utf8)
    exit 0
}

if (-not ($args -contains '-a')) {
    # Single video: <url> -P <root> -o 'Singles/%(title)s.%(ext)s'
    $id = ($args[0] -split 'v=')[1]
    $entry = $fixture | Where-Object { $_.Id -eq $id }
    $name = (Arg '-o').Replace('%(title)s', $entry.Title).Replace('%(ext)s', 'm4a')
    $path = Join-Path (Arg '-P') $name
    New-Item -ItemType Directory -Force -Path (Split-Path $path) | Out-Null
    [IO.File]::WriteAllText($path, "audio $id")
    exit 0
}

$batch = Arg '-a'; $root = Arg '-P'; $template = Arg '-o'
$n = [int](Arg '--autonumber-start'); $archive = Arg '--download-archive'
$code = 0
$urls = [IO.File]::ReadAllLines($batch)
[IO.File]::AppendAllText($env:FAKE_YTDLP_LOG, "batch: $(($urls | ForEach-Object { ($_ -split 'v=')[1] }) -join ',')`n", $utf8)
if ($env:FAKE_YTDLP_LISTFILE -and (Test-Path -LiteralPath $env:FAKE_YTDLP_LISTFILE)) {
    # Lets tests check the playlist link isn't added to the list before the download.
    $inList = [bool](Select-String -LiteralPath $env:FAKE_YTDLP_LISTFILE -SimpleMatch 'list=' -Quiet)
    [IO.File]::AppendAllText($env:FAKE_YTDLP_LOG, "list-had-link-during-download: $inList`n", $utf8)
}
foreach ($url in $urls) {
    $id = ($url -split 'v=')[1]
    $entry = $fixture | Where-Object { $_.Id -eq $id }
    if ($unavailable -contains $id) { Write-Output "ERROR: [youtube] ${id}: Video unavailable"; $code = 1; continue }
    $name = [regex]::Replace($template, '%\(autonumber\)0(\d+)d', { param($m) "$n".PadLeft([int]$m.Groups[1].Value, '0') })
    $name = $name.Replace('%(title)s', $entry.Title).Replace('%(ext)s', 'm4a').Replace('%%', '%')
    $path = Join-Path $root $name
    $n++
    if ($broken -contains $id) {
        [IO.File]::WriteAllText(($path -replace '\.m4a$', '.mp4.part'), 'partial')
        [IO.File]::WriteAllText(($path -replace '\.m4a$', '.mp4.part-Frag3'), 'partial')
        Write-Output "ERROR: Unable to download video $id"; $code = 1; continue
    }
    [IO.File]::WriteAllText($path, "audio $id")
    [IO.File]::AppendAllText($archive, "youtube $id`n", $utf8)
}
exit $code
