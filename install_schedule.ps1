<#
.SYNOPSIS
Registers a Task Scheduler task that runs update_all.ps1 every 15 minutes
while you are logged in, with no visible window.

.DESCRIPTION
update_all.ps1 exits immediately unless playlists.txt changed or a day has
passed, so the 15-minute interval costs nothing between real runs.

Run it again to update the task. Remove it with:
    Unregister-ScheduledTask -TaskName "yt-dlp playlist updates"

For a second person with their own YouTube account, register another task
with their own list, music folder and Firefox profile:
    install_schedule.ps1 -TaskName "yt-dlp playlists (sam)" -List D:\sync\sam\playlists.txt -Root D:\music\sam -Browser firefox:sam
#>
param(
    [string]$TaskName = 'yt-dlp playlist updates',
    [string]$List = (Join-Path $env:USERPROFILE "Downloads\yt_sync\playlists.txt"),
    [string]$Root = (Join-Path $env:USERPROFILE "Downloads\yt_playlists"),
    [string]$Browser = 'firefox'
)

$script = Join-Path $PSScriptRoot 'update_all.ps1'
# conhost --headless runs the console app without opening a window.
$arguments = "--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$script`" " +
    "-List `"$List`" -Root `"$Root`" -Browser `"$Browser`""

$action = New-ScheduledTaskAction -Execute 'conhost.exe' -Argument $arguments -WorkingDirectory $PSScriptRoot
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 15)
$settings = New-ScheduledTaskSettingsSet -MultipleInstances IgnoreNew -StartWhenAvailable `
    -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Hours 6)
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings `
    -Principal $principal -Description "Downloads new songs for every playlist in $List" -Force | Out-Null
Write-Host "Registered '$TaskName'. It checks $List every 15 minutes."
