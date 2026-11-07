import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Android-side helpers implemented in MainActivity.kt.
class NativeBridge {
  static const _channel = MethodChannel('tvcast/native');
  static const discoveryEvents = EventChannel('tvcast/discovery');
  static const _micEvents = EventChannel('tvcast/mic');

  /// 16-bit mono PCM chunks at 8 kHz while the microphone is running.
  static Stream<Uint8List> get micChunks =>
      _micEvents.receiveBroadcastStream().map((e) => e as Uint8List);

  static Future<bool> requestMicPermission() async {
    if (!isAndroid) return false;
    return await _channel.invokeMethod<bool>('micPermission') ?? false;
  }

  static Future<bool> startMic() async {
    if (!isAndroid) return false;
    return await _channel.invokeMethod<bool>('startMic') ?? false;
  }

  static Future<void> stopMic() async {
    if (!isAndroid) return;
    await _channel.invokeMethod('stopMic');
  }

  static bool get isAndroid => Platform.isAndroid;

  static Future<void> startDiscovery() async {
    if (!isAndroid) return;
    await _channel.invokeMethod('startDiscovery');
  }

  static Future<void> stopDiscovery() async {
    if (!isAndroid) return;
    await _channel.invokeMethod('stopDiscovery');
  }

  /// Opens the phone's built-in screen-cast picker. Returns which screen was
  /// opened ("cast", "wifi_display", "smart_view", "google_home") or null.
  static Future<String?> openScreenCast() async {
    if (!isAndroid) return null;
    return _channel.invokeMethod<String>('openScreenCast');
  }

  static Future<bool> openGoogleHome() async {
    if (!isAndroid) return false;
    return await _channel.invokeMethod<bool>('openGoogleHome') ?? false;
  }
}
