import 'dart:async';
import 'dart:io';
import 'dart:math';

/// Serves picked local files over HTTP so the TV can stream them.
/// Supports byte-range requests, which video players need for seeking.
class MediaServer {
  HttpServer? _server;
  final Map<String, File> _files = {};
  final _rnd = Random.secure();

  Future<int> _ensure() async {
    if (_server != null) return _server!.port;
    final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
    server.listen(_handle);
    _server = server;
    return server.port;
  }

  /// Returns a URL the TV at [tvHost] can use to fetch [file].
  Future<String> publish(File file, String tvHost) async {
    final port = await _ensure();
    final ip = await localAddressFor(tvHost);
    if (ip == null) {
      throw Exception(
        'Could not find this phone\'s Wi-Fi address. '
        'Make sure you are on the same Wi-Fi as the TV.',
      );
    }
    final token = List.generate(
      12,
      (_) => _rnd.nextInt(36).toRadixString(36),
    ).join();
    _files[token] = file;
    final name = Uri.encodeComponent(file.uri.pathSegments.last);
    return 'http://$ip:$port/m/$token/$name';
  }

  static Future<String?> localAddressFor(String tvHost) async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    final tvPrefix = tvHost.split('.').take(3).join('.');
    String? fallback;
    for (final iface in interfaces) {
      for (final addr in iface.addresses) {
        final a = addr.address;
        if (a.startsWith('$tvPrefix.')) return a;
        final private =
            a.startsWith('192.168.') ||
            a.startsWith('10.') ||
            RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a);
        if (private && (fallback == null || iface.name.startsWith('wlan'))) {
          fallback = a;
        }
      }
    }
    return fallback;
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    try {
      final seg = req.uri.pathSegments;
      final file = seg.length >= 2 && seg[0] == 'm' ? _files[seg[1]] : null;
      if (file == null || !await file.exists()) {
        res.statusCode = HttpStatus.notFound;
        await res.close();
        return;
      }
      final length = await file.length();
      res.headers
        ..set(HttpHeaders.contentTypeHeader, mimeFor(file.path))
        ..set(HttpHeaders.acceptRangesHeader, 'bytes')
        ..set('Access-Control-Allow-Origin', '*');

      var start = 0;
      var end = length - 1;
      final range = req.headers.value(HttpHeaders.rangeHeader);
      final m = range == null
          ? null
          : RegExp(r'bytes=(\d*)-(\d*)').firstMatch(range);
      if (m != null) {
        final s = m.group(1)!;
        final e = m.group(2)!;
        if (s.isEmpty && e.isNotEmpty) {
          start = max(0, length - int.parse(e));
        } else {
          start = int.tryParse(s) ?? 0;
          if (e.isNotEmpty) end = min(int.parse(e), length - 1);
        }
        if (start > end || start >= length) {
          res.statusCode = HttpStatus.requestedRangeNotSatisfiable;
          res.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
          await res.close();
          return;
        }
        res.statusCode = HttpStatus.partialContent;
        res.headers.set(
          HttpHeaders.contentRangeHeader,
          'bytes $start-$end/$length',
        );
      }
      res.contentLength = end - start + 1;
      if (req.method == 'HEAD') {
        await res.close();
        return;
      }
      await res.addStream(file.openRead(start, end + 1));
      await res.close();
    } catch (_) {
      try {
        await res.close();
      } catch (_) {}
    }
  }

  Future<void> close() async {
    await _server?.close(force: true);
    _server = null;
    _files.clear();
  }
}

String mimeFor(String path) {
  final ext = path.split('.').last.toLowerCase();
  return switch (ext) {
    'mp4' || 'm4v' => 'video/mp4',
    'mkv' => 'video/x-matroska',
    'webm' => 'video/webm',
    'mov' => 'video/quicktime',
    '3gp' => 'video/3gpp',
    'm3u8' => 'application/x-mpegurl',
    'mpd' => 'application/dash+xml',
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' || 'oga' => 'audio/ogg',
    'flac' => 'audio/flac',
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'gif' => 'image/gif',
    'webp' => 'image/webp',
    'bmp' => 'image/bmp',
    'heic' || 'heif' => 'image/heic',
    _ => 'video/mp4',
  };
}
