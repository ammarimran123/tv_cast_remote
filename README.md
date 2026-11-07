# TV Cast & Remote

A Flutter app that casts media to, mirrors your screen to, and controls **Android TV / Google TV** devices: Xiaomi Mi Box, Xiaomi TV Box S, Chromecast with Google TV, and other Android TV boxes.

## Features

**Device discovery and connection**
- Finds TVs automatically on the same Wi-Fi (mDNS: `_androidtvremote2._tcp` and `_googlecast._tcp`)
- Shows each device's name, model, IP address and connection status
- Connect by IP address when discovery is blocked
- Secure pairing: the TV shows a 6-character code, and the link is mutually authenticated TLS
- Remembers saved TVs, reconnects to the last one on launch, and reconnects automatically if the link drops

**Remote control** (Android TV Remote protocol v2, the same protocol the Google TV app uses)
- D-pad with OK, or a swipe touchpad
- Power, Input, Back, Home, Menu, Assistant, Search, Info
- Volume and channel buttons that repeat while held; mute; live volume level read from the TV
- Media keys, a number pad, Guide and Captions
- Keyboard: type text into the TV's search fields
- App shortcuts (YouTube, Netflix, Prime Video, Disney+, Spotify, Play Store, Kodi, Settings), or open any link or package
- Shows which app is in the foreground on the TV

**Casting** (Google Cast v2, Default Media Receiver)
- Photos, videos and music from the phone, streamed by a built-in HTTP server that supports seeking (range requests)
- Direct web links (MP4, M3U8/HLS, MP3, JPG…). YouTube and Netflix links open in the TV app instead
- Play/pause, seek, ±10/30 s, next/previous in a queue, cast volume and mute, stop

**Screen mirroring**
- Opens the phone's built-in Cast-screen picker (Google Cast mirroring), with fallbacks for Samsung Smart View and Google Home

## Run

```bash
flutter pub get
flutter run            # with an Android phone connected
flutter build apk      # build/app/outputs/flutter-apk/app-release.apk
flutter test           # protocol tests against a simulated TV
```

The phone and the TV must be on the same Wi-Fi network.

## Project layout

```
lib/
  protocol/   proto.dart (protobuf codec), der.dart (X.509/RSA), atv_pairing.dart,
              atv_remote.dart, cast_client.dart, key_codes.dart
  services/   discovery, connection manager, media server, persistent store
  ui/         remote, cast, mirror, devices, settings screens
android/.../MainActivity.kt   NsdManager discovery and screen-cast launcher
```

## Notes
- Android apps cannot capture the screen and send it over Cast themselves; Google keeps screen mirroring inside the system Cast feature. This app opens that flow for you.
- Mirroring is available on Android only. On iOS, discovery, the remote and casting still work.
