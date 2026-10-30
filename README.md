# Adaptive HLS stream

Generate a VOD HLS ladder from a video with FFmpeg, then serve it through S3-compatible storage or CloudFront.

## Requirements

- `ffmpeg` with `libx264`
- `ffprobe` (included with FFmpeg)

Install FFmpeg with your platform's package manager:

macOS or Linux with Homebrew:

```bash
brew install ffmpeg
```

Windows with WinGet:

```powershell
winget install -e --id Gyan.FFmpeg
```

## Generate HLS

```bash
./generate-hls.sh INPUT_VIDEO [OUTPUT_DIR]
```

Example:

```bash
./generate-hls.sh sample-animated-video.mp4 sample-hls
```

The generator creates `master.m3u8`, named rendition directories, and five-second MPEG-TS segments. It preserves the input as the highest rendition and adds each lower standard rung that does not upscale the source: 1080p, 720p, 480p, 360p, and 240p. It encodes the first audio track when present.

```text
sample-hls/
  master.m3u8
  1080p/index.m3u8
  720p/index.m3u8
  480p/index.m3u8
  360p/index.m3u8
  240p/index.m3u8
```

## LocalStack playback

The test players are `player.html` and `youtube-player.html`. With LocalStack running and an `adaptive-hls` bucket configured for browser reads:

```bash
awslocal s3 sync sample-hls s3://adaptive-hls
awslocal s3 cp player.html s3://adaptive-hls/player.html --content-type 'text/html; charset=utf-8'
awslocal s3 cp youtube-player.html s3://adaptive-hls/youtube-player.html --content-type 'text/html; charset=utf-8'
```

Open `http://localhost:4566/adaptive-hls/player.html` for the custom HLS player and `http://localhost:4566/adaptive-hls/youtube-player.html` for the YouTube embed.

## Gamepad support

Controllers use the browser’s standard gamepad mapping. Support marked **conditional** requires the source, browser, or connected device to expose that capability.

| Capability | YouTube IFrame API | `youtube-player.html` | Video.js + HLS | `player.html` |
| --- | --- | --- | --- | --- |
| Play/pause, seek, volume, mute | Yes | A/Start; D-pad or left stick; B | Yes | A; D-pad or left stick; B |
| Fullscreen | Host iframe only | Y | Yes | Y |
| Skip 10 seconds | Yes | Bumpers/triggers | Yes | Bumpers/triggers |
| Playback speed | Yes | Not bound after removing the custom menu | Yes | Native Settings: **Speed** |
| Manual quality selection | No; YouTube removed the API | No | Yes; pin a rendition or return to ABR Auto | Native Settings: **Quality** |
| Quality status | Change event only | No page-owned display | Active rendition and selection state | Native Settings: **Quality** |
| Captions/subtitles | Conditional caption font-size module only; no runtime visibility toggle | No | Conditional text-track toggle and selection | X; Native Settings: **Captions** |
| Alternate audio tracks | No | No | Conditional HLS audio renditions | Native Settings: **Audio** |
| Picture-in-picture | No IFrame Player API control | No | Conditional browser API | L3 |
| Remote playback / casting | No IFrame Player API control | No | Conditional browser API | R3 |
| YouTube Settings, Watch later, Share | No; cross-origin YouTube UI | No | Not applicable; this player owns its UI | Not applicable |

For `player.html`, **B9 / ☰ Hamburger** opens Video.js’s native Settings menu. D-pad or left stick up/down moves focus; A or right opens a category or selects its focused option; B, **B8 / Back**, or left closes the menu. The native menu omits unavailable source-dependent controls.
See [GAMEPAD_SUPPORT_REPORT.md](GAMEPAD_SUPPORT_REPORT.md) for API boundaries, controller mappings, source-dependent behavior, and browser verification.

## AWS S3 and CloudFront deployment

Create an S3 bucket and a CloudFront distribution whose S3 origin uses Origin Access Control (OAC). Keep S3 Block Public Access enabled; CloudFront, not public S3, serves the objects. Set the distribution's default root object to `player.html` if it is only for this test player.

Set the deployment values, then upload media segments before playlists so every published playlist has its referenced objects available:

```bash
export AWS_PROFILE=your-profile
export AWS_REGION=us-east-1
export BUCKET=your-hls-bucket
export DISTRIBUTION_ID=your-cloudfront-distribution-id
export OUTPUT_DIR=sample-hls

# Immutable VOD segments.
aws s3 sync "$OUTPUT_DIR/" "s3://$BUCKET/" \
  --exclude '*' --include '*.ts' \
  --content-type 'video/mp2t' \
  --cache-control 'public, max-age=31536000, immutable'

# Playlists must refresh so updated rendition references take effect.
aws s3 sync "$OUTPUT_DIR/" "s3://$BUCKET/" \
  --exclude '*' --include '*.m3u8' \
  --content-type 'application/vnd.apple.mpegurl' \
  --cache-control 'no-cache, max-age=0, must-revalidate'

aws s3 cp player.html "s3://$BUCKET/player.html" \
  --content-type 'text/html; charset=utf-8' \
  --cache-control 'no-cache, max-age=0, must-revalidate'

aws cloudfront create-invalidation \
  --distribution-id "$DISTRIBUTION_ID" \
  --paths '/*'

DOMAIN=$(aws cloudfront get-distribution \
  --id "$DISTRIBUTION_ID" \
  --query 'Distribution.DomainName' \
  --output text)
echo "https://$DOMAIN/player.html"
```

The CloudFront cache behavior must forward `GET` and `HEAD` to the S3 origin. No browser CORS configuration is needed when `player.html`, playlists, and segments use the same CloudFront domain.
