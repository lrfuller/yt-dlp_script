<#
.SYNOPSIS
Writes an M3U playlist into every subfolder of the playlist download folder.

.DESCRIPTION
Each subfolder of -Root gets "<folder name>.m3u" listing its audio files by
bare filename, ordered by the leading track number. Because the playlist sits
beside the songs and uses relative entries, the folder can be copied anywhere,
such as a phone's Music folder, and the playlist keeps working. VLC for
Android picks it up on its next library scan.

A playlist is only rewritten when its contents change.

.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File make_playlists.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File make_playlists.ps1 -Root "D:\Music"
#>
param(
    [string]$Root = (Join-Path $env:USERPROFILE "Downloads\yt_playlists")
)

$AudioExts = '.opus', '.m4a', '.mp3', '.aac', '.ogg', '.oga', '.flac', '.wav'

if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    Write-Host "No playlist folder at $Root"
    exit 1
}

# UTF-8 without BOM, LF line endings: what Android players expect.
$Utf8 = New-Object System.Text.UTF8Encoding $false

# Numbered files first by number (so "01" and "001" sort together), then by name.
$ByTrackNumber = @{ Expression = {
    if ($_.BaseName -match '^\s*(\d+)') { [double]$Matches[1] } else { [double]::MaxValue }
} }

foreach ($dir in Get-ChildItem -LiteralPath $Root -Directory) {
    $tracks = @(Get-ChildItem -LiteralPath $dir.FullName -File |
        Where-Object { $AudioExts -contains $_.Extension.ToLower() } |
        Sort-Object $ByTrackNumber, Name)
    if ($tracks.Count -eq 0) { continue }

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('#EXTM3U')
    foreach ($t in $tracks) {
        $lines.Add("#EXTINF:-1,$($t.BaseName)")
        # VLC reads entries as URLs: a raw '#' or '?' cuts the path short and VLC stops
        # reading the playlist there. Percent-encode those, and '%' itself first.
        $lines.Add($t.Name.Replace('%', '%25').Replace('#', '%23').Replace('?', '%3F'))
    }
    $text = ($lines -join "`n") + "`n"

    $out = Join-Path $dir.FullName "$($dir.Name).m3u"
    if ((Test-Path -LiteralPath $out) -and ([IO.File]::ReadAllText($out, $Utf8) -ceq $text)) { continue }
    [IO.File]::WriteAllText($out, $text, $Utf8)
    Write-Host "Playlist: $out ($($tracks.Count) tracks)"
}
