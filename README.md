# Adaptive HLS stream

Generate a VOD HLS ladder from a video with FFmpeg, then serve it through S3-compatible storage or CloudFront.

## Requirements

- `ffmpeg` with `libx264`
- `ffprobe`

## Generate HLS

```bash
./generate-hls.sh INPUT_VIDEO [OUTPUT_DIR]
```

Example:

```bash
./generate-hls.sh sample-animated-video.mp4 sample-hls
```

The generator creates `master.m3u8`, named rendition directories, and six-second MPEG-TS segments. It preserves the input as the highest rendition and adds each lower standard rung that does not upscale the source: 1080p, 720p, 480p, 360p, and 240p. It encodes the first audio track when present.

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

## AWS deployment

Sync MPEG-TS segments before playlists, then invalidate CloudFront. Cache segments for a long time and playlists briefly; see the AWS CLI commands used for your bucket/distribution configuration.
