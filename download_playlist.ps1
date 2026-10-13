<#
.SYNOPSIS
Downloads a YouTube playlist as audio into its own folder, fetching only the
songs that are new since the last pull, then writes the folder's .m3u.

.DESCRIPTION
Songs land in <Root>\<playlist title>\<NNN> - <title>.<ext>. The folder name is
fixed on the first pull, so renaming the playlist on YouTube doesn't split it.
A single-video link (no list=) goes to <Root>\Singles\<title>.<ext>.

Every downloaded video ID is logged in <Root>\.archive\<playlist id>.txt
(yt-dlp's --download-archive). On each run:

1. The playlist is listed without downloading.
2. Songs already in the playlist folder but missing from the log (folders
   made before the log existed, or copied back from a phone) are matched by
   title and added to the log, so they are not downloaded again.
3. Only songs not in the log are downloaded. They are numbered after the
   highest number already in the folder, oldest addition first, so existing
   files are never renamed and the end of the playlist is always the newest.

No song is ever deleted. A song removed from YouTube keeps its local copy and
stays in the .m3u. The only files removed are yt-dlp's partial-download files
(.part, .ytdl) and any .mp4/.webm written during this run.

Only one run per playlist and folder at a time; a second one is skipped.

Exit codes: 0 done, 1 some videos failed or the playlist couldn't be listed,
2 skipped because another run of this playlist is in progress.

If the -List file exists, the playlist's link is added to it after the
download, so playlists downloaded by hand are kept up to date by
update_all.ps1 too.

.PARAMETER Browser
Where yt-dlp reads YouTube cookies from: "firefox", or "firefox:<profile>"
for a profile signed into a different account.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File download_playlist.ps1 -Url "https://www.youtube.com/playlist?list=PL..."
#>
param(
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$Root = (Join-Path $env:USERPROFILE "Downloads\yt_playlists"),
    [string]$Browser = 'firefox',
    [string]$List = (Join-Path $env:USERPROFILE "Downloads\yt_sync\playlists.txt"),
    # yt-dlp executable; tests point this at a fake.
    [string]$YtDlp = 'yt-dlp'
)

. (Join-Path $PSScriptRoot 'common.ps1')

$Common = @(
    '--cookies-from-browser', $Browser,
    '--extractor-args', 'youtube:player_client=default,web_safari;player_js_version=actual',
    '--remote-components', 'ejs:github'
)
$Download = @('-x', '--audio-format', 'best', '--no-keep-video', '--throttled-rate', '1M', '-N', '8')
$Utf8 = New-Object System.Text.UTF8Encoding $false
$MakePlaylists = Join-Path $PSScriptRoot 'make_playlists.ps1'

New-Item -ItemType Directory -Force -Path $Root | Out-Null

# A single video (no list=): no numbering, no log.
if ($Url -notmatch '[?&]list=([\w-]+)') {
    & $YtDlp $Url -P $Root -o 'Singles/%(title)s.%(ext)s' @Common @Download
    $code = [int]($LASTEXITCODE -ne 0)
    & $MakePlaylists -Root $Root
    exit $code
}
$listId = $Matches[1]

# Two runs of one playlist would download in-flight songs twice and delete each
# other's partial files, e.g. a manual pull while the scheduled update fires.
$lock = New-Object System.Threading.Mutex($false, "yt-dlp-script-playlist-$(Get-RootKey $Root)-$listId")
# Abandoned = a run whose window was closed mid-download; the lock is ours now.
try { $locked = $lock.WaitOne(0) } catch [System.Threading.AbandonedMutexException] { $locked = $true }
if (-not $locked) {
    Write-Host "Already being downloaded (scheduled update or another window): $Url. Skipped."
    exit 2
}

try {
    # 1. List the playlist. yt-dlp writes each entry's ID and its sanitized
    #    "<folder>\<title>" path to a UTF-8 file, so unicode titles survive.
    $listing = [IO.Path]::GetTempFileName()
    try {
        & $YtDlp $Url --flat-playlist -o '%(playlist_title|Singles)s/%(title)s' --print-to-file "%(id)s`t%(filename)s" $listing @Common
        $entries = @(foreach ($line in [IO.File]::ReadAllLines($listing, $Utf8)) {
            $id, $path = $line -split "`t", 2
            $folder, $title = $path -split '[\\/]', 2
            [pscustomobject]@{ Id = $id; Folder = $folder; Title = $title }
        })
    } finally {
        Remove-Item -LiteralPath $listing -ErrorAction SilentlyContinue
    }
    if ($entries.Count -eq 0) {
        Write-Host "Could not list the playlist. Check the link, and that Firefox is signed in for private playlists."
        exit 1
    }

    $archive = Join-Path $Root ".archive\$listId.txt"
    New-Item -ItemType Directory -Force -Path (Split-Path $archive) | Out-Null

    # Keep the folder from the first pull, so a rename on YouTube doesn't split the playlist.
    $folderFile = Join-Path $Root ".archive\$listId.folder"
    $folder = $entries[0].Folder
    if (Test-Path -LiteralPath $folderFile) {
        $pinned = [IO.File]::ReadAllText($folderFile, $Utf8).Trim()
        if ($pinned -and (Test-Path -LiteralPath (Join-Path $Root $pinned))) { $folder = $pinned }
    }
    [IO.File]::WriteAllText($folderFile, $folder, $Utf8)
    $dir = Join-Path $Root $folder
    New-Item -ItemType Directory -Force -Path $dir | Out-Null

    $known = New-Object 'System.Collections.Generic.HashSet[string]'
    if (Test-Path -LiteralPath $archive) {
        foreach ($line in [IO.File]::ReadAllLines($archive, $Utf8)) { [void]$known.Add(($line -split ' ', 2)[-1]) }
    }

    # 2. Adopt songs already in the folder that the log doesn't know about.
    $files = @(Get-ChildItem -LiteralPath $dir -File | Where-Object { $AudioExts -contains $_.Extension.ToLower() })
    $titlesOnDisk = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($f in $files) { [void]$titlesOnDisk.Add(($f.BaseName -replace $TrackPrefix, '')) }

    $adopted = @($entries | Where-Object { -not $known.Contains($_.Id) -and $titlesOnDisk.Contains($_.Title) })
    if ($adopted.Count -gt 0) {
        [IO.File]::AppendAllText($archive, (($adopted | ForEach-Object { "youtube $($_.Id)`n" }) -join ''), $Utf8)
        foreach ($e in $adopted) { [void]$known.Add($e.Id) }
        Write-Host "Matched $($adopted.Count) song(s) already in '$folder' by title."
    }

    # 3. Download what's left, numbered after the highest existing number.
    $new = @($entries | Where-Object { -not $known.Contains($_.Id) -and $_.Title -notmatch '^\[(Deleted|Private) video\]$' })
    $code = 0
    if ($new.Count -eq 0) {
        Write-Host "'$folder' is up to date. No new songs."
    } else {
        # Playlists set to "add new videos to top" list the newest first; reverse so
        # the oldest new song gets the lowest number.
        $firstNew = [array]::IndexOf($entries, $new[0])
        $firstKnown = -1
        for ($i = 0; $i -lt $entries.Count; $i++) { if ($known.Contains($entries[$i].Id)) { $firstKnown = $i; break } }
        if ($firstKnown -ge 0 -and $firstNew -lt $firstKnown) { [array]::Reverse($new) }

        $numbers = @($files | Where-Object { $_.BaseName -match $TrackNumber } | ForEach-Object { $Matches[1] })
        $next = 1 + (@($numbers | ForEach-Object { [int]$_ }) + 0 | Measure-Object -Maximum).Maximum
        $width = [Math]::Max(3, (@($numbers | ForEach-Object { $_.Length }) + 0 | Measure-Object -Maximum).Maximum)

        Write-Host "Downloading $($new.Count) new song(s) into '$folder', starting at number $next."
        $batch = [IO.Path]::GetTempFileName()
        $started = [DateTime]::UtcNow
        $before = if (Test-Path -LiteralPath $archive) { @([IO.File]::ReadAllLines($archive)).Count } else { 0 }
        try {
            [IO.File]::WriteAllLines($batch, [string[]]($new | ForEach-Object { "https://www.youtube.com/watch?v=$($_.Id)" }))
            $template = $folder.Replace('%', '%%') + "/%(autonumber)0${width}d - %(title)s.%(ext)s"
            & $YtDlp -a $batch -P $Root -o $template --autonumber-start $next --download-archive $archive @Common @Download
            # Any yt-dlp failure is 1; 2 is reserved for "skipped".
            $code = [int]($LASTEXITCODE -ne 0)
        } finally {
            Remove-Item -LiteralPath $batch -ErrorAction SilentlyContinue
            # Partial files of failed or killed runs can't be resumed: a retry gets a new
            # number, so a new name. yt-dlp's own temp files go whatever their age (the
            # lock means no other run owns them); .mp4/.webm only if this run wrote them.
            Get-ChildItem -LiteralPath $dir -File |
                Where-Object { $_.Name -match '\.(part|ytdl)$|\.part-Frag\d+' -or
                    ($_.Name -match '\.(mp4|webm)$' -and $_.LastWriteTimeUtc -ge $started) } |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
        $got = @([IO.File]::ReadAllLines($archive)).Count - $before
        Write-Host "Downloaded $got of $($new.Count) new song(s) into '$folder'."
    }

    # After the download, so a manual pull doesn't wake the scheduler mid-download.
    if ((Test-Path -LiteralPath $List) -and -not (Select-String -LiteralPath $List -SimpleMatch "list=$listId" -Quiet)) {
        # Phone editors often leave no trailing newline; don't glue onto the last line.
        $text = [IO.File]::ReadAllText($List)
        $sep = if ($text.Length -gt 0 -and -not $text.EndsWith("`n")) { "`n" } else { '' }
        [IO.File]::AppendAllText($List, "$sep" + "https://www.youtube.com/playlist?list=$listId`n", $Utf8)
        Write-Host "Added to $List"
    }

    & $MakePlaylists -Root $Root
    exit $code
} finally {
    $lock.ReleaseMutex()
}
