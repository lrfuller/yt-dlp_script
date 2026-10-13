# Dot-sourced by download_playlist.ps1, make_playlists.ps1 and update_all.ps1, so
# they agree on what counts as a song, how its track number is read, and how a
# music folder is keyed for locks.

# Audio formats yt-dlp's -x can produce, plus common ones already in a folder.
$AudioExts = '.opus', '.m4a', '.mp3', '.aac', '.ogg', '.oga', '.flac', '.wav'

# "007 - Title" -> track number 7, and the title without its number.
$TrackNumber = '^\s*(\d+)'
$TrackPrefix = '^\s*\d+\s*-\s*'

# Short stable key for a music folder, so locks for different people's folders
# never collide.
function Get-RootKey([string]$Root) {
    $bytes = [Text.Encoding]::UTF8.GetBytes([IO.Path]::GetFullPath($Root).TrimEnd('\').ToLowerInvariant())
    [BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($bytes)).Replace('-', '').Substring(0, 16)
}
