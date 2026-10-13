<#
.SYNOPSIS
Updates every playlist in playlists.txt. Meant to run from Task Scheduler
(see install_schedule.ps1).

.DESCRIPTION
-List holds one YouTube playlist link per line; blank lines and lines starting
with # are ignored. Each link goes through download_playlist.ps1, so only new
songs download. Deleting a line stops updates for that playlist; nothing is
ever deleted from -Root.

Scheduled every 15 minutes, it does real work only when the list changed since
the last run, or the last run is older than -MaxAgeHours. -Force always runs.

A short summary is written to last_run.txt next to the list (readable on the
phone when the list folder is synced), and the full output is appended to
<Root>\.archive\update.log.

.PARAMETER Browser
Where yt-dlp reads YouTube cookies from: "firefox", or "firefox:<profile>"
for a profile signed into a different account.
#>
param(
    [string]$List = (Join-Path $env:USERPROFILE "Downloads\yt_sync\playlists.txt"),
    [string]$Root = (Join-Path $env:USERPROFILE "Downloads\yt_playlists"),
    [string]$Browser = 'firefox',
    [int]$MaxAgeHours = 24,
    [switch]$Force,
    # yt-dlp executable; tests point this at a fake.
    [string]$YtDlp = 'yt-dlp'
)

$Utf8 = New-Object System.Text.UTF8Encoding $false
$env:PYTHONIOENCODING = 'utf-8'
try { [Console]::OutputEncoding = $Utf8 } catch { }

# One run at a time, even if started by hand while the schedule fires.
$mutex = New-Object System.Threading.Mutex($false, 'yt-dlp-script-update-all')
if (-not $mutex.WaitOne(0)) { Write-Host "Another update is already running."; exit 0 }

try {
    $stateDir = Join-Path $Root '.archive'
    New-Item -ItemType Directory -Force -Path $stateDir, (Split-Path $List) | Out-Null
    $state = Join-Path $stateDir 'update_state.txt'
    $log = Join-Path $stateDir 'update.log'
    $summary = Join-Path (Split-Path $List) 'last_run.txt'

    if (-not (Test-Path -LiteralPath $List)) {
        [IO.File]::WriteAllText($List, "# One YouTube playlist link per line. Delete a line to stop updating it.`n", $Utf8)
    }

    $hash = (Get-FileHash -LiteralPath $List -Algorithm SHA256).Hash
    if (-not $Force -and (Test-Path -LiteralPath $state)) {
        $fresh = ((Get-Date) - (Get-Item -LiteralPath $state).LastWriteTime).TotalHours -lt $MaxAgeHours
        if ($fresh -and ([IO.File]::ReadAllText($state).Trim() -eq $hash)) { exit 0 }
    }

    $urls = @([IO.File]::ReadAllLines($List, $Utf8) | ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('#') })

    $started = Get-Date
    [IO.File]::AppendAllText($log, "`n===== $($started.ToString('yyyy-MM-dd HH:mm')) =====`n", $Utf8)
    $report = New-Object System.Collections.Generic.List[string]
    $report.Add("Last run: $($started.ToString('yyyy-MM-dd HH:mm'))")

    foreach ($url in $urls) {
        # The list can be edited from the phone; only ever hand yt-dlp YouTube playlist links.
        if ($url -notmatch '^https://(www\.|m\.|music\.)?youtube\.com/[^\s]*[?&]list=[\w-]+') {
            $report.Add("Skipped, not a YouTube playlist link: $url")
            continue
        }
        $lines = @(& (Join-Path $PSScriptRoot 'download_playlist.ps1') -Url $url -Root $Root -Browser $Browser -List $List -YtDlp $YtDlp *>&1 |
            ForEach-Object { "$_" })
        $code = $LASTEXITCODE
        [IO.File]::AppendAllText($log, (($lines -join "`n") + "`n"), $Utf8)

        $status = $lines | Where-Object { $_ -match "^(Downloading \d+ new song|'.+' is up to date|Could not list)" } | Select-Object -Last 1
        if (-not $status) { $status = "No result for $url" }
        if ($code -ne 0) { $status += "  (some songs failed; see update.log on the PC)" }
        $report.Add($status)
    }
    if ($urls.Count -eq 0) { $report.Add("playlists.txt has no links yet.") }

    [IO.File]::WriteAllText($summary, (($report -join "`n") + "`n"), $Utf8)
    # Re-hash: download_playlist.ps1 may have normalized links into the list.
    [IO.File]::WriteAllText($state, (Get-FileHash -LiteralPath $List -Algorithm SHA256).Hash, $Utf8)
    Write-Host ($report -join "`n")
} finally {
    $mutex.ReleaseMutex()
}
