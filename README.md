# YouTube Video Downloader

A simple Windows batch script for downloading YouTube videos and playlists in MP4 or MP3 format using yt-dlp.

## Features

- Download individual videos as MP4 or MP3
- Download entire playlists as MP3 files
- Automatic quality selection (best available)
- Interactive menu-driven interface
- Built-in dependency checking
- Error handling and user-friendly messages

## Prerequisites

Before using this script, you need to install the following dependencies:

### 1. yt-dlp (Required)
The core downloader tool.

**Installation:**
```bash
# Using pip (recommended)
pip install yt-dlp

# Or download the executable
# Visit: https://github.com/yt-dlp/yt-dlp/releases
```

### 2. Firefox (Required)
This script uses Firefox cookies for YouTube authentication, which provides the most reliable downloads.

**Setup Steps:**
1. Download and install Firefox: https://www.mozilla.org/firefox/
2. Open Firefox and navigate to YouTube
3. Sign in with your YouTube/Google account
4. Keep Firefox installed (the script reads cookies from Firefox)

**Why Firefox?**
- Most reliable cookie extraction with yt-dlp
- Better success rate with age-restricted and premium content
- Consistent authentication across downloads

### 3. Deno (Required for YouTube downloads)
JavaScript runtime needed to solve YouTube's anti-bot challenges.

**Installation:**
```bash
# Windows (PowerShell)
irm https://deno.land/install.ps1 | iex

# Or download installer from:
# https://deno.land/
```

**Alternative:** Node.js can be used instead of Deno
- Download from: https://nodejs.org/

### 4. ffmpeg (Required for MP4 downloads)
Needed to merge separate video and audio streams into a single MP4 file.

**Installation:**
1. Download from: https://github.com/BtbN/FFmpeg-Builds/releases
2. Extract the downloaded archive
3. Add the `bin` folder to your system PATH

**Adding to PATH:**
1. Right-click "This PC" → Properties
2. Advanced System Settings → Environment Variables
3. Under "System variables", find and edit "Path"
4. Click "New" and add the path to ffmpeg's `bin` folder
5. Click OK to save

## Usage

### Running the Script

1. Double-click `1_yt_download.bat` or run it from command prompt
2. The script will check for all required dependencies
3. Select your desired output format:
   - **Option 1:** MP4 video (best resolution, AV1 preferred, video and audio merged)
   - **Option 2:** MP3 audio only (single video)
   - **Option 3:** Audio only (entire playlist, original audio format)
   - **Option 4:** Any available video format (single pre-merged file, no ffmpeg merge)

4. Paste the YouTube URL when prompted
5. Wait for the download to complete
6. Enter another URL or type 'exit' to quit

### Example Workflow

```
Select output format:
1. mp4 output
2. mp3 output
3. mp3 output for YouTube playlists
4. any available video format (single file, no merge)
Enter your choice (1, 2, 3, or 4): 1

What youtube video do you want to download? (or type 'exit' to stop): https://www.youtube.com/watch?v=dQw4w9WgXcQ
Downloading as MP4...
[download] Downloading video...
Download complete!

What youtube video do you want to download? (or type 'exit' to stop): exit
Exiting...
```

## Output Locations

Downloaded files are saved to:
- **Single videos (options 1, 2, 4):** `%USERPROFILE%\Downloads\youtubeVids\`
- **Playlists (option 3):** `%USERPROFILE%\Downloads\yt_playlists\`

These folders are created automatically.

## Troubleshooting

### Slow Downloads
- The script already re-fetches the stream URL when speed drops below 1 MB/s (`--throttled-rate 1M`)
- If a download is still slow, press Ctrl+C and run it again with the same URL; it resumes where it stopped
- Update yt-dlp: `yt-dlp -U`

### MP4 Won't Play
- Option 1 downloads AV1 video. VLC plays it as-is
- Windows Media Player / Films & TV need the free "AV1 Video Extension" from the Microsoft Store

### "Requested format is not available" Error
- Ensure ffmpeg is installed and in your PATH
- Make sure you're signed into YouTube in Firefox
- Try updating yt-dlp: `yt-dlp -U`

### "n challenge solving failed" Warning
- Install Deno or Node.js (Deno recommended)
- The script uses `--remote-components ejs:github` to handle this automatically

### Downloads Fail or Return 403 Errors
- Verify you're signed into YouTube in Firefox
- Make sure Firefox is installed and accessible
- Try clearing Firefox cache and signing in again
- Update yt-dlp to the latest version
- Occasional one-off 403s come from YouTube itself; rerun the download

### MP3 Downloads Work but MP4 Fails
- This usually means ffmpeg is not installed or not in your PATH
- Verify ffmpeg installation: `ffmpeg -version` in command prompt

### Script Shows "Firefox not detected"
- Install Firefox from https://www.mozilla.org/firefox/
- The script looks in the standard install folders (`Program Files`, `Program Files (x86)`, `%LocalAppData%`); a Firefox installed elsewhere is not detected, but cookies still work if yt-dlp can find the profile

## Technical Details

### Format Selection
- **MP4:** Uses `bv[protocol=https]+ba/bv+ba/b` with `--merge-output-format mp4`. Prefers regular HTTPS streams (usually AV1) over YouTube's HLS "Premium" streams, which are ~10x larger at the same resolution. Falls back to any stream if no HTTPS one exists
- **MP3:** Extracts audio and converts to MP3 format
- **Playlists:** Downloads all videos in order with numbered filenames, keeping the original audio format
- **Any format:** Uses `b[vcodec!=none]/b` (best file that already contains video and audio)

### Download Speed
- `--throttled-rate 1M`: if YouTube serves a throttled stream URL, yt-dlp re-extracts a fresh one and resumes
- `-N 8`: downloads 8 fragments at once for fragmented (HLS/DASH) streams

### Authentication
The script uses `--cookies-from-browser firefox` to authenticate with YouTube using your Firefox cookies. This allows downloading:
- Age-restricted content
- Private/unlisted videos (if you have access)
- Premium quality streams (if you have YouTube Premium)

### Anti-Bot Protection
YouTube uses JavaScript challenges to prevent automated downloads. The script handles this with:
- `--remote-components ejs:github` flag
- Deno/Node.js runtime for executing challenge scripts
- Custom player client parameters for reliability

## Privacy & Security

- Your credentials are never stored or transmitted by this script
- Cookies are read directly from Firefox's local storage
- All downloads happen locally on your machine
- No data is sent to third parties

## Legal Notice

This tool is for personal use only. Please respect:
- YouTube's Terms of Service
- Copyright laws in your jurisdiction
- Content creators' rights

Only download content you have the right to download.

## Updates

Keep yt-dlp updated for best compatibility:
```bash
yt-dlp -U
```

YouTube frequently changes their API, so regular updates are important.

## Credits

- Built with [yt-dlp](https://github.com/yt-dlp/yt-dlp)
- Uses [ffmpeg](https://ffmpeg.org/) for media processing
- Powered by [Deno](https://deno.land/) for JavaScript execution

## License

This script is provided as-is for personal use. No warranty or support is provided.
