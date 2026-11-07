import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'proto.dart';

const _nsConnection = 'urn:x-cast:com.google.cast.tp.connection';
const _nsHeartbeat = 'urn:x-cast:com.google.cast.tp.heartbeat';
const _nsReceiver = 'urn:x-cast:com.google.cast.receiver';
const _nsMedia = 'urn:x-cast:com.google.cast.media';

/// Google's Default Media Receiver: plays video, audio and images by URL.
const defaultMediaReceiver = 'CC1AD845';

class CastMediaStatus {
  final String playerState; // IDLE, PLAYING, PAUSED, BUFFERING
  final double currentTime;
  final double? duration;
  final String? idleReason;
  final DateTime receivedAt;

  CastMediaStatus({
    required this.playerState,
    required this.currentTime,
    this.duration,
    this.idleReason,
  }) : receivedAt = DateTime.now();

  bool get isPlaying => playerState == 'PLAYING';

  /// Playback position extrapolated from the last status update.
  double get position {
    if (!isPlaying) return currentTime;
    final p =
        currentTime +
        DateTime.now().difference(receivedAt).inMilliseconds / 1000.0;
    return duration == null ? p : p.clamp(0, duration!).toDouble();
  }
}

/// Google Cast v2 sender (TLS, port 8009) speaking to the Default Media
/// Receiver. Works with Chromecast and any Android TV with Chromecast
/// built-in (Mi Box, TV Box S, Chromecast with Google TV, ...).
class CastClient {
  final String host;
  final int port;

  SecureSocket? _socket;
  final List<int> _buf = [];
  Timer? _heartbeat;
  int _requestId = 1;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};

  String? _transportId;
  String? _sessionId;
  int? _mediaSessionId;

  double volume = 1;
  bool muted = false;
  CastMediaStatus? media;

  void Function()? onChanged;
  void Function()? onDisconnected;

  CastClient(this.host, {this.port = 8009});

  bool get isConnected => _socket != null;
  bool get hasMedia => _mediaSessionId != null;

  Future<void> connect() async {
    if (_socket != null) return;
    final socket = await SecureSocket.connect(
      host,
      port,
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 8),
    );
    _socket = socket;
    socket.listen(
      _onData,
      onError: (_) => _drop(),
      onDone: _drop,
      cancelOnError: true,
    );
    _sendJson(_nsConnection, 'receiver-0', {'type': 'CONNECT'});
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      _sendJson(_nsHeartbeat, 'receiver-0', {'type': 'PING'});
    });
    await _request(_nsReceiver, 'receiver-0', {'type': 'GET_STATUS'});
  }

  void _onData(Uint8List data) {
    _buf.addAll(data);
    while (_buf.length >= 4) {
      final len = ByteData.sublistView(Uint8List.fromList(_buf.sublist(0, 4)))
          .getUint32(0);
      if (_buf.length < 4 + len) break;
      final frame = _buf.sublist(4, 4 + len);
      _buf.removeRange(0, 4 + len);
      try {
        _handle(ProtoMessage.decode(frame));
      } catch (_) {}
    }
  }

  void _handle(ProtoMessage m) {
    final source = m.stringField(2);
    final ns = m.stringField(4);
    final payload = m.stringField(6);
    if (payload.isEmpty) return;
    final json = jsonDecode(payload) as Map<String, dynamic>;
    final type = json['type'];

    if (ns == _nsHeartbeat && type == 'PING') {
      _sendJson(_nsHeartbeat, source, {'type': 'PONG'});
      return;
    }
    if (ns == _nsConnection && type == 'CLOSE') {
      if (source == _transportId) _resetSession();
      onChanged?.call();
      return;
    }
    if (type == 'RECEIVER_STATUS') {
      final status = json['status'] as Map<String, dynamic>? ?? {};
      final vol = status['volume'] as Map<String, dynamic>?;
      if (vol != null) {
        volume = (vol['level'] as num?)?.toDouble() ?? volume;
        muted = vol['muted'] as bool? ?? muted;
      }
      final apps = (status['applications'] as List?) ?? const [];
      final app = apps.cast<Map<String, dynamic>>().where(
        (a) => a['appId'] == defaultMediaReceiver,
      );
      if (app.isEmpty && _transportId != null) _resetSession();
    }
    if (type == 'MEDIA_STATUS') {
      final list = (json['status'] as List?) ?? const [];
      if (list.isEmpty) {
        _mediaSessionId = null;
        media = null;
      } else {
        final s = list.first as Map<String, dynamic>;
        _mediaSessionId = s['mediaSessionId'] as int?;
        final mediaInfo = s['media'] as Map<String, dynamic>?;
        media = CastMediaStatus(
          playerState: s['playerState'] as String? ?? 'IDLE',
          currentTime: (s['currentTime'] as num?)?.toDouble() ?? 0,
          duration:
              (mediaInfo?['duration'] as num?)?.toDouble() ?? media?.duration,
          idleReason: s['idleReason'] as String?,
        );
      }
    }
    final id = json['requestId'];
    if (id is int && id != 0) _pending.remove(id)?.complete(json);
    onChanged?.call();
  }

  void _resetSession() {
    _transportId = null;
    _sessionId = null;
    _mediaSessionId = null;
    media = null;
  }

  void _sendJson(String ns, String dest, Map<String, dynamic> payload) {
    final s = _socket;
    if (s == null) return;
    final body =
        (ProtoWriter()
              ..int32(1, 0)
              ..string(2, 'sender-0')
              ..string(3, dest)
              ..string(4, ns)
              ..int32(5, 0)
              ..string(6, jsonEncode(payload)))
            .toBytes();
    final header = ByteData(4)..setUint32(0, body.length);
    try {
      s.add([...header.buffer.asUint8List(), ...body]);
    } catch (_) {
      _drop();
    }
  }

  Future<Map<String, dynamic>> _request(
    String ns,
    String dest,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 15),
  }) {
    final id = _requestId++;
    final c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _sendJson(ns, dest, {...payload, 'requestId': id});
    return c.future.timeout(
      timeout,
      onTimeout: () {
        _pending.remove(id);
        throw TimeoutException('The TV did not respond to ${payload['type']}');
      },
    );
  }

  Future<void> _ensureReceiver() async {
    await connect();
    if (_transportId != null) return;
    final res = await _request(_nsReceiver, 'receiver-0', {
      'type': 'LAUNCH',
      'appId': defaultMediaReceiver,
    }, timeout: const Duration(seconds: 25));
    if (res['type'] == 'LAUNCH_ERROR') {
      throw Exception('The TV could not start the media player.');
    }
    Map<String, dynamic>? app;
    var status = res;
    for (var attempt = 0; attempt < 5 && app == null; attempt++) {
      final apps = ((status['status'] as Map?)?['applications'] as List?) ?? [];
      for (final a in apps.cast<Map<String, dynamic>>()) {
        if (a['appId'] == defaultMediaReceiver && a['transportId'] != null) {
          app = a;
        }
      }
      if (app == null) {
        await Future<void>.delayed(const Duration(milliseconds: 600));
        status = await _request(_nsReceiver, 'receiver-0', {
          'type': 'GET_STATUS',
        });
      }
    }
    if (app == null) throw Exception('Media player did not start on the TV.');
    _transportId = app['transportId'] as String;
    _sessionId = app['sessionId'] as String?;
    _sendJson(_nsConnection, _transportId!, {'type': 'CONNECT'});
  }

  /// Loads [url] on the TV and starts playback.
  Future<void> load(
    String url, {
    required String contentType,
    String? title,
    String? subtitle,
  }) async {
    await _ensureReceiver();
    final isImage = contentType.startsWith('image/');
    final res = await _request(_nsMedia, _transportId!, {
      'type': 'LOAD',
      'autoplay': true,
      'currentTime': 0,
      'media': {
        'contentId': url,
        'contentUrl': url,
        'contentType': contentType,
        'streamType': isImage ? 'NONE' : 'BUFFERED',
        'metadata': {
          'metadataType': isImage
              ? 4
              : (contentType.startsWith('audio/') ? 3 : 0),
          if (title != null) 'title': title,
          if (subtitle != null) 'subtitle': subtitle,
        },
      },
    }, timeout: const Duration(seconds: 30));
    if (res['type'] == 'LOAD_FAILED' || res['type'] == 'LOAD_CANCELLED') {
      throw Exception('The TV could not play this media.');
    }
    if (res['type'] == 'INVALID_REQUEST') {
      throw Exception(
        'The TV rejected the media: ${res['reason'] ?? 'unknown'}',
      );
    }
  }

  void _mediaCommand(String type, [Map<String, dynamic> extra = const {}]) {
    final t = _transportId;
    final m = _mediaSessionId;
    if (t == null || m == null) return;
    _sendJson(_nsMedia, t, {
      'type': type,
      'mediaSessionId': m,
      'requestId': _requestId++,
      ...extra,
    });
  }

  void play() => _mediaCommand('PLAY');
  void pause() => _mediaCommand('PAUSE');
  void seek(double seconds) => _mediaCommand('SEEK', {'currentTime': seconds});
  void refreshStatus() {
    final t = _transportId;
    if (t != null) {
      _sendJson(_nsMedia, t, {'type': 'GET_STATUS', 'requestId': _requestId++});
    }
  }

  void setVolume(double level) {
    volume = level.clamp(0, 1).toDouble();
    _sendJson(_nsReceiver, 'receiver-0', {
      'type': 'SET_VOLUME',
      'volume': {'level': volume},
      'requestId': _requestId++,
    });
  }

  void setMuted(bool value) {
    muted = value;
    _sendJson(_nsReceiver, 'receiver-0', {
      'type': 'SET_VOLUME',
      'volume': {'muted': value},
      'requestId': _requestId++,
    });
  }

  /// Stops playback and closes the media player on the TV.
  void stop() {
    final session = _sessionId;
    if (session != null) {
      _sendJson(_nsReceiver, 'receiver-0', {
        'type': 'STOP',
        'sessionId': session,
        'requestId': _requestId++,
      });
    }
    _resetSession();
    onChanged?.call();
  }

  void _drop() {
    _heartbeat?.cancel();
    _heartbeat = null;
    final s = _socket;
    _socket = null;
    s?.destroy();
    _resetSession();
    for (final c in _pending.values) {
      if (!c.isCompleted)
        c.completeError(const SocketException('Disconnected'));
    }
    _pending.clear();
    if (s != null) onDisconnected?.call();
  }

  Future<void> close() async {
    onDisconnected = null;
    _drop();
  }
}
