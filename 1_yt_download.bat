@echo off

REM Check for JavaScript runtime
where deno >nul 2>nul
if %errorlevel% neq 0 (
    where node >nul 2>nul
    if %errorlevel% neq 0 (
        echo WARNING: No JavaScript runtime detected!
        echo yt-dlp requires a JS runtime to download YouTube videos.
        echo.
        echo Recommended: Install Deno from https://deno.land/
        echo Alternative: Install Node.js from https://nodejs.org/
        echo.
        echo Press any key to continue anyway (downloads may fail^)...
        pause >nul
    )
)

REM Check for ffmpeg
where ffmpeg >nul 2>nul
if %errorlevel% neq 0 (
    echo WARNING: ffmpeg not detected!
    echo ffmpeg is required to merge video and audio streams for MP4 downloads.
    echo.
    echo Download from: https://github.com/BtbN/FFmpeg-Builds/releases
    echo After downloading, extract and add the 'bin' folder to your system PATH.
    echo.
    echo Press any key to continue anyway (MP4 downloads may fail^)...
    pause >nul
)

REM Check for Firefox
where firefox >nul 2>nul
if %errorlevel% neq 0 (
    echo WARNING: Firefox not detected!
    echo This script uses Firefox cookies for authentication with YouTube.
    echo.
    echo REQUIRED STEPS:
    echo 1. Install Firefox from https://www.mozilla.org/firefox/
    echo 2. Open Firefox and sign in to YouTube with your account
    echo 3. Keep Firefox installed (cookies are needed for downloads^)
    echo.
    echo Press any key to continue anyway (downloads will likely fail^)...
    pause >nul
) else (
    echo NOTE: This script uses cookies from Firefox.
    echo Make sure you are signed in to YouTube in Firefox for best results.
    echo.
)

REM Display options
echo.
echo Select output format:
echo 1. mp4 output
echo 2. mp3 output
echo 3. mp3 output for YouTube playlists
set /p choice="Enter your choice (1, 2, or 3): "

REM Validate choice
if not "%choice%"=="1" if not "%choice%"=="2" if not "%choice%"=="3" (
    echo Invalid choice. Please run the script again and select 1, 2, or 3.
    pause
    exit /b 1
)

REM Main download loop
:download_loop
echo.
set /p video_url="What youtube video do you want to download? (or type 'exit' to stop): "

REM Check if user wants to exit
if /i "%video_url%"=="exit" (
    echo Exiting...
    pause
    exit /b 0
)

REM Check if URL is provided
if "%video_url%"=="" (
    echo Error: No URL provided. Please try again.
    goto download_loop
)

REM Execute based on user choice
if "%choice%"=="1" (
    echo Downloading as MP4...
    yt-dlp "%video_url%" -f "bv+ba/b" -P youtubeVids --cookies-from-browser firefox --extractor-args "youtube:player_client=default,web_safari;player_js_version=actual" --remote-components ejs:github
    if errorlevel 1 (
        echo Download failed or was cancelled.
    ) else (
        echo Download complete!
    )
) else if "%choice%"=="2" (
    echo Downloading as MP3...
    yt-dlp "%video_url%" --extract-audio --audio-format mp3 -P youtubeVids --remote-components ejs:github
    if errorlevel 1 (
        echo Download failed or was cancelled.
    ) else (
        echo Download complete!
    )
) else if "%choice%"=="3" (
    echo Downloading playlist as MP3...
    yt-dlp -o "%%(playlist_index)s - %%(title)s.%%(ext)s" -x --audio-format best --no-keep-video "%video_url%" --extractor-args "youtube:player_client=default,web_safari;player_js_version=actual" -P yt_playlists --remote-components ejs:github
    if errorlevel 1 (
        echo Download failed or was cancelled.
    ) else (
        echo Download complete!
    )
)

echo.
REM Loop back to ask for another URL
goto download_loop
