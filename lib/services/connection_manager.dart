import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/tv_device.dart';
import '../protocol/atv_pairing.dart';
import '../protocol/atv_remote.dart';
import '../protocol/cast_client.dart';
import 'app_store.dart';
import 'media_server.dart';

enum LinkState {
  disconnected,
  preparing,
  connecting,
  pairing,
  connected,
  reconnecting,
}

class CastItem {
  final String title;
  final String? path;
  final String? url;
  final String contentType;
  CastItem({
    required this.title,
    this.path,
    this.url,
    required this.contentType,
  });

  bool get isImage => contentType.startsWith('image/');
  bool get isAudio => contentType.startsWith('audio/');
}

/// Owns the live connection to the selected TV: the remote-control link,
/// the Cast media session and pairing.
class ConnectionManager extends ChangeNotifier {
  final AppStore store;
  ConnectionManager(this.store);

  TvDevice? device;
  LinkState state = LinkState.disconnected;
  String? error;

  AtvRemote? _remote;
  AtvPairing? _pairing;
  CastClient? _cast;
  final MediaServer _server = MediaServer();

  TvVolume? volume;
  bool? tvOn;
  String? currentApp;

  List<CastItem> queue = [];
  int queueIndex = -1;
  bool castBusy = false;
  Timer? _ticker;
  int _reconnectAttempt = 0;
  bool _userDisconnect = false;

  bool get isConnected => state == LinkState.connected;
  bool get remoteReady => _remote?.isConnected ?? false;
  CastClient? get cast => _cast;
  CastMediaStatus? get media => _cast?.media;
  CastItem? get nowPlaying =>
      queueIndex >= 0 && queueIndex < queue.length && _cast?.hasMedia == true
      ? queue[queueIndex]
      : null;

  void _set(LinkState s, {String? err}) {
    state = s;
    error = err;
    notifyListeners();
  }

  Future<void> connect(TvDevice target) async {
    if (device?.host != target.host) await disconnect();
    _userDisconnect = false;
    final saved = store.saved(target.host);
    if (saved != null && !identical(saved, target)) {
      final name = saved.name;
      saved.mergeFrom(target);
      saved.name = name;
    }
    device = saved ?? target;
    _set(store.hasIdentity ? LinkState.connecting : LinkState.preparing);

    try {
      await store.identity();
      _set(LinkState.connecting);
      final d = device!;
      final tryRemote = d.supportsRemote || !d.supportsCast;
      if (tryRemote) {
        try {
          await _openRemote(d);
          await _onConnected();
          return;
        } on AtvNotPairedException {
          await _startPairing();
          return;
        } on SocketException {
          if (d.supportsCast) {
            await _onConnected();
            return;
          }
          // Unknown manual device: see if it at least speaks Cast.
          if (await _probeCast(d)) {
            d.supportsCast = true;
            d.supportsRemote = false;
            await _onConnected();
            return;
          }
          rethrow;
        }
      }
      await _onConnected();
    } catch (e) {
      _set(LinkState.disconnected, err: _friendly(e));
    }
  }

  Future<bool> _probeCast(TvDevice d) async {
    try {
      final s = await SecureSocket.connect(
        d.host,
        d.castPort,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 4),
      );
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openRemote(TvDevice d) async {
    final identity = await store.identity();
    final remote = AtvRemote(d.host, identity, port: d.remotePort);
    remote
      ..onVolume = (v) {
        volume = v;
        notifyListeners();
      }
      ..onPower = (on) {
        tvOn = on;
        notifyListeners();
      }
      ..onCurrentApp = (pkg) {
        currentApp = pkg;
        notifyListeners();
      }
      ..onDeviceInfo = (model, vendor) {
        if (model.isNotEmpty && d.model.isEmpty) {
          d.model = vendor.isEmpty ? model : '$vendor $model';
        }
      }
      ..onDisconnected = _onRemoteLost;
    await remote.connect();
    _remote = remote;
    d.supportsRemote = true;
    d.paired = true;
  }

  Future<void> _onConnected() async {
    final d = device!;
    d.online = true;
    d.lastConnected = DateTime.now();
    _reconnectAttempt = 0;
    await store.saveDevice(d, markLast: true);
    _set(LinkState.connected);
  }

  Future<void> _startPairing() async {
    final identity = await store.identity();
    await _pairing?.close();
    _pairing = AtvPairing(device!.host, identity, port: device!.pairingPort);
    await _pairing!.start();
    _set(LinkState.pairing);
  }

  Future<void> restartPairing() async {
    try {
      _set(LinkState.connecting);
      await _startPairing();
    } catch (e) {
      _set(LinkState.disconnected, err: _friendly(e));
    }
  }

  /// Returns null on success, or an error message to show next to the code.
  Future<String?> submitPairingCode(String code) async {
    final pairing = _pairing;
    if (pairing == null) return 'Pairing session expired. Start again.';
    try {
      await pairing.finish(code);
    } on PairingException catch (e) {
      if (e.badCode && !e.sessionAlive) {
        // The TV drops the session after a rejected code; start a fresh one.
        unawaited(restartPairing());
        return '${e.message} A new code is shown on the TV.';
      }
      return e.message;
    } catch (e) {
      return _friendly(e);
    }
    await pairing.close();
    _pairing = null;
    try {
      _set(LinkState.connecting);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _openRemote(device!);
      await _onConnected();
      return null;
    } catch (e) {
      _set(LinkState.disconnected, err: _friendly(e));
      return _friendly(e);
    }
  }

  Future<void> cancelPairing() async {
    await _pairing?.close();
    _pairing = null;
    if (device?.supportsCast == true) {
      await _onConnected();
    } else {
      _set(LinkState.disconnected);
    }
  }

  void _onRemoteLost() {
    _remote = null;
    if (_userDisconnect || device == null) return;
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_reconnectAttempt >= 6) {
      _set(LinkState.disconnected, err: 'Lost connection to ${device?.name}.');
      return;
    }
    _set(LinkState.reconnecting);
    final delay = Duration(seconds: [1, 2, 3, 5, 8, 13][_reconnectAttempt]);
    _reconnectAttempt++;
    Timer(delay, () async {
      if (_userDisconnect || device == null || remoteReady) return;
      try {
        await _openRemote(device!);
        _reconnectAttempt = 0;
        _set(LinkState.connected);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  /// Called when the app returns to the foreground.
  void resume() {
    if (device != null &&
        !_userDisconnect &&
        device!.supportsRemote &&
        !remoteReady &&
        state != LinkState.pairing &&
        state != LinkState.reconnecting) {
      _reconnectAttempt = 0;
      _scheduleReconnect();
    }
  }

  Future<void> disconnect() async {
    _userDisconnect = true;
    _ticker?.cancel();
    await _remote?.close();
    _remote = null;
    await _pairing?.close();
    _pairing = null;
    await _cast?.close();
    _cast = null;
    await _server.close();
    volume = null;
    tvOn = null;
    currentApp = null;
    queueIndex = -1;
    device = null;
    _set(LinkState.disconnected);
  }

  // ---------------- Remote control ----------------

  void key(int code) => _remote?.sendKey(code);
  void keyLong(int code, bool down) =>
      _remote?.sendKey(code, direction: down ? 1 : 2);
  void text(String t) => _remote?.sendText(t);
  void openLink(String link) => _remote?.launchApp(link);

  // ---------------- Casting ----------------

  Future<CastClient> _castClient() async {
    final d = device;
    if (d == null) throw Exception('Connect to a TV first.');
    if (_cast == null) {
      final c = CastClient(d.host, port: d.castPort)
        ..onChanged = notifyListeners
        ..onDisconnected = () {
          _cast = null;
          notifyListeners();
        };
      _cast = c;
    }
    await _cast!.connect();
    d.supportsCast = true;
    _ticker ??= Timer.periodic(const Duration(seconds: 1), (t) {
      if (_cast?.hasMedia == true) {
        if (t.tick % 5 == 0) _cast!.refreshStatus();
        notifyListeners();
      }
    });
    return _cast!;
  }

  void setQueue(List<CastItem> items) {
    queue = items;
    queueIndex = -1;
    notifyListeners();
  }

  /// Casts [queue] item [index]. Returns an error message or null.
  Future<String?> playIndex(int index) async {
    if (index < 0 || index >= queue.length) return null;
    castBusy = true;
    notifyListeners();
    try {
      final item = queue[index];
      final client = await _castClient();
      final url =
          item.url ?? await _server.publish(File(item.path!), device!.host);
      await client.load(url, contentType: item.contentType, title: item.title);
      queueIndex = index;
      return null;
    } catch (e) {
      return _friendly(e);
    } finally {
      castBusy = false;
      notifyListeners();
    }
  }

  Future<String?> next() => playIndex(queueIndex + 1);
  Future<String?> previous() => playIndex(queueIndex - 1);

  void stopCasting() {
    _cast?.stop();
    queueIndex = -1;
    notifyListeners();
  }

  String _friendly(Object e) {
    if (e is SocketException) {
      return 'Could not reach the TV. Check that it is on and on the same Wi-Fi.';
    }
    if (e is TimeoutException) return 'The TV took too long to respond.';
    if (e is PairingException) return e.message;
    if (e is AtvNotPairedException) return e.toString();
    final s = e.toString();
    return s.startsWith('Exception: ') ? s.substring(11) : s;
  }

  @override
  void dispose() {
    disconnect();
    super.dispose();
  }
}
