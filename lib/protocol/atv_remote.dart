import 'dart:async';
import 'dart:io';

import 'atv_pairing.dart';
import 'der.dart';
import 'key_codes.dart';
import 'proto.dart';

/// The TV refused our client certificate: pairing is required.
class AtvNotPairedException implements Exception {
  @override
  String toString() => 'This TV needs to be paired first.';
}

class TvVolume {
  final int level;
  final int max;
  final bool muted;
  const TvVolume(this.level, this.max, this.muted);
  double get fraction => max == 0 ? 0 : level / max;
}

/// Android TV Remote v2 control channel (TLS, port 6466).
class AtvRemote {
  final String host;
  final int port;
  final ClientIdentity identity;

  SecureSocket? _socket;
  final _decoder = VarintFrameDecoder();
  Timer? _watchdog;
  DateTime _lastMessage = DateTime.now();

  int _imeCounter = 0;
  int _fieldCounter = 0;
  bool _imeKnown = false;

  /// Feature flags: PING | KEY | IME | POWER | VOLUME | APP_LINK.
  static const _features = 1 | 2 | 4 | 32 | 64 | 512;

  void Function()? onDisconnected;
  void Function(TvVolume volume)? onVolume;
  void Function(bool isOn)? onPower;
  void Function(String package)? onCurrentApp;
  void Function(String model, String vendor)? onDeviceInfo;

  AtvRemote(this.host, this.identity, {this.port = 6466});

  bool get isConnected => _socket != null;

  /// Connects and completes once the TV accepts our configuration. Throws
  /// [AtvNotPairedException] when the TV rejects the certificate.
  Future<void> connect() async {
    final ready = Completer<void>();
    SecureSocket socket;
    try {
      socket = await SecureSocket.connect(
        host,
        port,
        context: clientContext(identity),
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 8),
      );
    } on HandshakeException {
      throw AtvNotPairedException();
    } on TlsException {
      throw AtvNotPairedException();
    }
    _socket = socket;
    _lastMessage = DateTime.now();

    socket.listen(
      (data) {
        _lastMessage = DateTime.now();
        for (final frame in _decoder.add(data)) {
          try {
            _handle(ProtoMessage.decode(frame), ready);
          } catch (_) {
            // Ignore messages we cannot parse; the protocol has many extras.
          }
        }
      },
      onError: (Object e) {
        if (!ready.isCompleted) {
          ready.completeError(
            e is TlsException || e is HandshakeException
                ? AtvNotPairedException()
                : e,
          );
        }
        _drop();
      },
      onDone: () {
        // An unpaired client is disconnected before the TV says anything.
        if (!ready.isCompleted) ready.completeError(AtvNotPairedException());
        _drop();
      },
      cancelOnError: true,
    );

    try {
      await ready.future.timeout(const Duration(seconds: 10));
    } catch (_) {
      _drop(notify: false);
      rethrow;
    }

    _watchdog = Timer.periodic(const Duration(seconds: 5), (_) {
      // The TV pings every ~5s; silence means the link is dead.
      if (DateTime.now().difference(_lastMessage) >
          const Duration(seconds: 16)) {
        _drop();
      }
    });
  }

  void _handle(ProtoMessage m, Completer<void> ready) {
    if (m.has(1)) {
      // remote_configure from TV -> reply with ours.
      final info = m.message(1)?.message(2);
      if (info != null) {
        onDeviceInfo?.call(info.stringField(1), info.stringField(2));
      }
      _send(
        ProtoWriter()..message(
          1,
          ProtoWriter()
            ..int32(1, _features)
            ..message(
              2,
              ProtoWriter()
                ..string(1, 'TV Cast & Remote')
                ..string(2, 'Flutter')
                ..int32(3, 1)
                ..string(4, '1')
                ..string(5, 'atvremote')
                ..string(6, '1.0.0'),
            ),
        ),
      );
    } else if (m.has(2)) {
      // remote_set_active
      _send(ProtoWriter()..message(2, ProtoWriter()..int32(1, _features)));
      if (!ready.isCompleted) ready.complete();
    } else if (m.has(8)) {
      final val = m.message(8)?.intField(1) ?? 0;
      _send(ProtoWriter()..message(9, ProtoWriter()..int32(1, val)));
    } else if (m.has(20)) {
      // remote_ime_key_inject: carries the foreground app.
      final pkg = m.message(20)?.message(1)?.stringField(12) ?? '';
      if (pkg.isNotEmpty) onCurrentApp?.call(pkg);
    } else if (m.has(21)) {
      final edit = m.message(21)!;
      _imeCounter = edit.intField(1);
      _fieldCounter = edit.intField(2);
      _imeKnown = true;
    } else if (m.has(40)) {
      onPower?.call(m.message(40)?.boolField(1) ?? false);
    } else if (m.has(50)) {
      final v = m.message(50)!;
      onVolume?.call(TvVolume(v.intField(7), v.intField(6), v.boolField(8)));
    }
  }

  void _send(ProtoWriter msg) {
    final s = _socket;
    if (s == null) return;
    try {
      s.add(varintFramed(msg.toBytes()));
    } catch (_) {
      _drop();
    }
  }

  void sendKey(int keyCode, {int direction = KeyDirection.short}) {
    _send(
      ProtoWriter()..message(
        10,
        ProtoWriter()
          ..int32(1, keyCode)
          ..int32(2, direction),
      ),
    );
  }

  /// Opens a deep link on the TV (e.g. a YouTube or Netflix URL).
  void launchApp(String link) {
    _send(ProtoWriter()..message(90, ProtoWriter()..string(1, link)));
  }

  /// Types [text] into the focused text field on the TV.
  void sendText(String text) {
    if (text.isEmpty) return;
    if (_imeKnown) {
      final pos = text.length - 1;
      _send(
        ProtoWriter()..message(
          21,
          ProtoWriter()
            ..int32(1, _imeCounter)
            ..int32(2, _fieldCounter)
            ..message(
              3,
              ProtoWriter()
                ..int32(1, 1)
                ..message(
                  2,
                  ProtoWriter()
                    ..int32(1, pos)
                    ..int32(2, pos)
                    ..string(3, text),
                ),
            ),
        ),
      );
      return;
    }
    // Fallback: emulate key presses for characters we can map.
    for (final ch in text.split('')) {
      final code = TvKey.forChar(ch);
      if (code != null) sendKey(code);
    }
  }

  void _drop({bool notify = true}) {
    _watchdog?.cancel();
    _watchdog = null;
    final s = _socket;
    _socket = null;
    s?.destroy();
    if (s != null && notify) onDisconnected?.call();
  }

  Future<void> close() async {
    onDisconnected = null;
    _drop(notify: false);
  }
}
