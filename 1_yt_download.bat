@echo off

REM Display options
echo.
echo Select output format:
echo 1. mp4 output
echo 2. mp3 output
set /p choice="Enter your choice (1 or 2): "

REM Validate choice
if not "%choice%"=="1" if not "%choice%"=="2" (
    echo Invalid choice. Please run the script again and select 1 or 2
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
    yt-dlp "%video_url%" --extract-audio --audio-format mp3 -P youtubeVids
     if errorlevel 1 (
        echo Download failed or was cancelled.
    ) else (
        echo Download complete!
    )
) 

REM Loop back to ask for another URL
goto download_loop

