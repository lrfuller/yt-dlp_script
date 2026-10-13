# Shared by download_playlist.ps1 and make_playlists.ps1 (dot-sourced), so both
# agree on what counts as a song and how its track number is read.

# Audio formats yt-dlp's -x can produce, plus common ones already in a folder.
$AudioExts = '.opus', '.m4a', '.mp3', '.aac', '.ogg', '.oga', '.flac', '.wav'

# "007 - Title" -> track number 7; numberless files sort after numbered ones.
$TrackNumber = '^\s*(\d+)'
$TrackPrefix = '^\s*\d+\s*-\s*'
