import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/tv_device.dart';
import '../protocol/der.dart';

/// Persistent app state: saved devices, client identity and preferences.
class AppStore extends ChangeNotifier {
  late SharedPreferences _prefs;
  final Map<String, TvDevice> _saved = {};

  ThemeMode themeMode = ThemeMode.dark;
  bool haptics = true;
  bool autoConnect = true;
  String? lastDeviceHost;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs.getString('devices');
    if (raw != null) {
      for (final j in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        final d = TvDevice.fromJson(j);
        _saved[d.host] = d;
      }
    }
    themeMode =
        ThemeMode.values[_prefs.getInt('themeMode') ?? ThemeMode.dark.index];
    haptics = _prefs.getBool('haptics') ?? true;
    autoConnect = _prefs.getBool('autoConnect') ?? true;
    lastDeviceHost = _prefs.getString('lastDevice');
  }

  List<TvDevice> get savedDevices => _saved.values.toList()
    ..sort(
      (a, b) => (b.lastConnected ?? DateTime(2000)).compareTo(
        a.lastConnected ?? DateTime(2000),
      ),
    );

  TvDevice? saved(String host) => _saved[host];

  TvDevice? get lastDevice =>
      lastDeviceHost == null ? null : _saved[lastDeviceHost!];

  Future<void> saveDevice(TvDevice d, {bool markLast = false}) async {
    _saved[d.host] = d;
    if (markLast) {
      lastDeviceHost = d.host;
      await _prefs.setString('lastDevice', d.host);
    }
    await _persistDevices();
  }

  Future<void> forgetDevice(String host) async {
    _saved.remove(host);
    if (lastDeviceHost == host) {
      lastDeviceHost = null;
      await _prefs.remove('lastDevice');
    }
    await _persistDevices();
  }

  Future<void> _persistDevices() async {
    await _prefs.setString(
      'devices',
      jsonEncode(_saved.values.map((d) => d.toJson()).toList()),
    );
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    await _prefs.setInt('themeMode', m.index);
    notifyListeners();
  }

  Future<void> setHaptics(bool v) async {
    haptics = v;
    await _prefs.setBool('haptics', v);
    notifyListeners();
  }

  Future<void> setAutoConnect(bool v) async {
    autoConnect = v;
    await _prefs.setBool('autoConnect', v);
    notifyListeners();
  }

  // ---- Client identity (certificate used for TV pairing) ----

  ClientIdentity? _identity;

  Future<ClientIdentity> identity() async {
    if (_identity != null) return _identity!;
    final cert = _prefs.getString('clientCert');
    final key = _prefs.getString('clientKey');
    if (cert != null && key != null) {
      try {
        return _identity = ClientIdentity.fromPems(cert, key);
      } catch (_) {}
    }
    final id = await compute(_generateIdentity, null);
    await _prefs.setString('clientCert', id.certPem);
    await _prefs.setString('clientKey', id.keyPem);
    return _identity = id;
  }

  bool get hasIdentity => _prefs.containsKey('clientCert');

  /// Discards the pairing certificate; every TV must be paired again.
  Future<void> resetIdentity() async {
    _identity = null;
    await _prefs.remove('clientCert');
    await _prefs.remove('clientKey');
    for (final d in _saved.values) {
      d.paired = false;
    }
    await _persistDevices();
  }
}

ClientIdentity _generateIdentity(void _) => ClientIdentity.generate();
