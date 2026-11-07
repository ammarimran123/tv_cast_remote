import 'dart:io';

import 'package:flutter/services.dart';

/// Android-side helpers implemented in MainActivity.kt.
class NativeBridge {
  static const _channel = MethodChannel('tvcast/native');
  static const discoveryEvents = EventChannel('tvcast/discovery');

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
