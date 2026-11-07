/// Android `KeyEvent` key codes understood by the Android TV Remote service.
abstract final class TvKey {
  static const home = 3;
  static const back = 4;
  static const num0 = 7; // num0..num9 are 7..16
  static const dpadUp = 19;
  static const dpadDown = 20;
  static const dpadLeft = 21;
  static const dpadRight = 22;
  static const dpadCenter = 23;
  static const volumeUp = 24;
  static const volumeDown = 25;
  static const power = 26;
  static const a = 29; // a..z are 29..54
  static const comma = 55;
  static const period = 56;
  static const space = 62;
  static const enter = 66;
  static const del = 67;
  static const menu = 82;
  static const search = 84;
  static const playPause = 85;
  static const stop = 86;
  static const next = 87;
  static const previous = 88;
  static const rewind = 89;
  static const fastForward = 90;
  static const mute = 164;
  static const info = 165;
  static const channelUp = 166;
  static const channelDown = 167;
  static const guide = 172;
  static const captions = 175;
  static const settings = 176;
  static const tvInput = 178;
  static const assist = 219;
  static const sleep = 223;
  static const wakeup = 224;

  static int digit(int n) => num0 + n;

  /// Best-effort key code for a single character, or null if unmapped.
  static int? forChar(String ch) {
    final c = ch.toLowerCase();
    final code = c.codeUnitAt(0);
    if (code >= 0x61 && code <= 0x7a) return a + (code - 0x61);
    if (code >= 0x30 && code <= 0x39) return num0 + (code - 0x30);
    return switch (c) {
      ' ' => space,
      '.' => period,
      ',' => comma,
      '\n' => enter,
      _ => null,
    };
  }
}

/// Key press direction values from the remote protocol.
abstract final class KeyDirection {
  static const startLong = 1;
  static const endLong = 2;
  static const short = 3;
}
