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

The test player is `player.html`. With LocalStack running and an `adaptive-hls` bucket configured for browser reads:

```bash
awslocal s3 sync sample-hls s3://adaptive-hls
awslocal s3 cp player.html s3://adaptive-hls/player.html --content-type 'text/html; charset=utf-8'
```

Open `http://localhost:4566/adaptive-hls/player.html`, then use **Settings → Quality**. The player uses Video.js 10 with hls.js and selects Auto by default.

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
