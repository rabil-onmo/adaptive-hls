# Gamepad Support Research Report

## Scope

Comparison of browser-gamepad support for the two demo players:

- `youtube-player.html`: YouTube video `Q5Lvtjzde6o` through the YouTube IFrame Player API.
- `player.html`: self-hosted adaptive HLS through Video.js 10 and `hlsjs-video`.

The controller layer uses the browser [Gamepad API](https://developer.mozilla.org/en-US/docs/Web/API/Gamepad_API): `gamepadconnected` starts polling, `navigator.getGamepads()` provides current controller state, and `requestAnimationFrame()` processes it. Actions are triggered on a press edge, preventing a held button from repeatedly toggling an action every frame.

## Controller mapping

The browser normalizes supported devices to the [standard gamepad mapping](https://w3c.github.io/gamepad/#remapping). Physical labels vary by controller; indexes below are the browser-standard values.

| Input | Standard index | YouTube demo | HLS demo |
| --- | ---: | --- | --- |
| A / Cross | 0 | Play/pause | Play/pause; activate focused native Settings item |
| B / Circle | 1 | Mute/unmute | Mute/unmute; close native Settings |
| X / Square | 2 | — | Toggle captions/subtitles when present |
| Y / Triangle | 3 | Fullscreen | Fullscreen |
| Left bumper / trigger | 4 / 6 | Seek −10 seconds | Seek −10 seconds |
| Right bumper / trigger | 5 / 7 | Seek +10 seconds | Seek +10 seconds |
| B8 / Back | 8 | — | Back / close native Settings |
| B9 / ☰ Hamburger | 9 | Play/pause | Open native Settings |
| L3 | 10 | — | Picture-in-picture when browser support permits |
| R3 | 11 | — | Remote-playback chooser when browser/device support permits |
| D-pad / left stick horizontal | 12–15 / axis 0 | Seek ±5 seconds | Seek ±5 seconds; right activates and left closes native Settings |
| D-pad / left stick vertical | 12–15 / axis 1 | Volume ±5% | Volume ±5%; moves native Settings focus |

## Capability comparison

| Capability | YouTube IFrame API | `youtube-player.html` | Video.js + HLS | `player.html` |
| --- | --- | --- | --- | --- |
| Play/pause | `playVideo()`, `pauseVideo()` | Supported | Native media controls | Supported |
| Seek | `getCurrentTime()`, `getDuration()`, `seekTo()` | Supported for finite VOD duration | Native media timeline | Supported for finite VOD duration |
| Volume and mute | `getVolume()`, `setVolume()`, `mute()`, `unMute()` | Supported | Native media controls | Supported |
| Fullscreen | Host page can fullscreen the iframe element | Supported | Native fullscreen control | Supported |
| Playback rate | `getAvailablePlaybackRates()`, `setPlaybackRate()` | API supports it; intentionally not exposed after removing the custom YouTube menu | Video.js native Settings | Native Settings: Speed |
| Manual rendition quality | **Unavailable.** YouTube removed the IFrame API methods for getting or setting quality. | Not possible | Video.js native Settings | Native Settings: Quality |
| Quality status | `onPlaybackQualityChange` event only | Not displayed | Native quality menu reflects current choice | Native Settings: Quality |
| Captions/subtitles visibility and track choice | **Unavailable.** The supported captions module only exposes `fontSize` and `reload`; it has no runtime visibility or language-selection action. | Not possible | Native captions control and Settings | X and native Settings, conditional on text tracks |
| Caption font size | Conditional captions module option | Not exposed after removing the custom YouTube menu | Styling is browser/player UI dependent | Native skin control when supplied by player UI |
| Alternate audio tracks | No IFrame Player API action | Not possible | Video.js native Settings | Native Settings: Audio, conditional on multiple HLS audio tracks |
| Picture-in-picture | No IFrame Player API action | Not possible | Native picture-in-picture control | L3, conditional on browser permission/support |
| Remote playback / casting | No generic IFrame Player API action | Not possible | Native cast control | R3, conditional on available device/browser support |
| YouTube Settings UI, Watch later, Share | Not available to host page | Not possible | Not a third-party iframe; UI is page-owned | Page can expose its own controls |

## Why the YouTube controls stop where they do

The YouTube player is an iframe hosted on YouTube’s origin. Same-origin policy prevents the demo page from reading its DOM, focusing its internal controls, or clicking the native gear, Watch later, Share, or account buttons.

The supported integration boundary is the [YouTube IFrame Player API](https://developers.google.com/youtube/iframe_api_reference). It deliberately offers playback methods and selected events, not control over YouTube-owned UI or account state. The API documentation records that playback-quality selection and retrieval are no longer supported. A host-side quality selector would therefore be misleading because it could not reliably change the stream rendition.

## Why the self-hosted HLS player supports more

`player.html` is not embedded from a third-party origin. The page owns the player, source, UI, and controller bindings.

Video.js’s video preset includes playback, playback-rate, quality, audio-track, fullscreen, picture-in-picture, remote-playback, and text-track controls. The gamepad bridge focuses and activates those existing native controls rather than duplicating their UI.

`hlsjs-video` exposes the HLS renditions and audio tracks while its hls.js/MSE engine is active. The native Settings menu omits Audio when the manifest offers fewer than two tracks and Captions when the source has no captions/subtitles tracks.

## Adaptive quality behavior

Auto is the default and recommended quality state. It allows hls.js ABR to react to bandwidth and playback conditions. Selecting a fixed rendition is user-controlled override: it can improve predictability but may buffer if bandwidth is insufficient. Selecting Auto restores adaptive behavior.

Manual quality selection requires an HLS/DASH source with multiple renditions and an active streaming engine. A single-rendition source has no meaningful quality choice.

## Verification performed

### HLS player

A real browser loaded `player.html` from LocalStack with the five-rendition HLS ladder. A simulated standard gamepad exercised the live page:

- B9 opened Video.js’s native Settings menu; no page-owned settings overlay was present.
- A opened Quality; Down then A changed Auto to 240p.
- B closed the native menu.
- A started playback, B unmuted it, and D-pad right sought from 1 to 12 seconds.
- Browser console: no errors.

### YouTube player

A real browser loaded `youtube-player.html` and YouTube video `Q5Lvtjzde6o`.

- The IFrame Player API reported ready.
- The custom settings overlay was absent.
- Gamepad connection and direct volume input were processed.
- Browser console: no errors.

## Operational limits

1. A controller must be exposed by the operating system and browser using the standard mapping. Nonstandard controllers can report different physical button layouts.
2. Gamepad APIs are often disclosed to a page only after a controller interaction while the page is visible.
3. Picture-in-picture and remote playback depend on browser implementation, permission policy, and device availability.
4. Captions, alternate audio, and manual rendition selection depend on tracks/renditions declared by the current HLS manifest.
5. YouTube’s native settings and account surfaces remain outside the host page’s control by design.
