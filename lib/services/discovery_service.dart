import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:multicast_dns/multicast_dns.dart';

import '../models/tv_device.dart';
import 'native_bridge.dart';

const atvRemoteService = '_androidtvremote2._tcp';
const castService = '_googlecast._tcp';

/// Finds Android TV / Google Cast devices on the local network via mDNS.
/// Android uses the system NsdManager (reliable, handles multicast locks);
/// other platforms fall back to a pure-Dart mDNS client.
class DiscoveryService extends ChangeNotifier {
  final Map<String, TvDevice> _found = {};
  StreamSubscription<dynamic>? _sub;
  Timer? _stopTimer;
  bool scanning = false;

  List<TvDevice> get devices =>
      _found.values.toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  Future<void> scan({Duration duration = const Duration(seconds: 12)}) async {
    await stop();
    _found.clear();
    scanning = true;
    notifyListeners();
    _stopTimer = Timer(duration, stop);
    if (Platform.isAndroid) {
      _sub = NativeBridge.discoveryEvents.receiveBroadcastStream().listen(
        (e) => _onNative(Map<String, dynamic>.from(e as Map)),
        onError: (_) {},
      );
      await NativeBridge.startDiscovery();
    } else {
      unawaited(_dartScan(duration));
    }
  }

  void _onNative(Map<String, dynamic> e) {
    final host = e['host'] as String?;
    if (host == null || host.isEmpty || host.contains(':')) return;
    final attrs = Map<String, dynamic>.from(e['attrs'] as Map? ?? {});
    _add(
      host,
      e['type'] as String? ?? '',
      e['name'] as String? ?? host,
      e['port'] as int? ?? 0,
      attrs.map((k, v) => MapEntry(k, '$v')),
    );
  }

  void _add(
    String host,
    String type,
    String serviceName,
    int port,
    Map<String, String> txt,
  ) {
    final isCast = type.contains('googlecast');
    final device = TvDevice(
      host: host,
      name: isCast ? (txt['fn'] ?? serviceName) : serviceName,
      model: isCast ? (txt['md'] ?? '') : '',
      supportsCast: isCast,
      supportsRemote: !isCast,
      castPort: isCast ? port : 8009,
      remotePort: isCast ? 6466 : port,
      online: true,
    );
    final existing = _found[host];
    if (existing == null) {
      _found[host] = device;
    } else {
      // Prefer the friendly Cast name, but keep remote capability.
      final keepName = existing.supportsCast && !isCast;
      final oldName = existing.name;
      existing.mergeFrom(device);
      if (keepName) existing.name = oldName;
    }
    notifyListeners();
  }

  Future<void> _dartScan(Duration duration) async {
    final client = MDnsClient();
    try {
      await client.start();
      for (final type in [atvRemoteService, castService]) {
        final ptrName = '$type.local';
        await for (final ptr
            in client
                .lookup<PtrResourceRecord>(
                  ResourceRecordQuery.serverPointer(ptrName),
                )
                .timeout(duration ~/ 2, onTimeout: (s) => s.close())) {
          await for (final srv in client.lookup<SrvResourceRecord>(
            ResourceRecordQuery.service(ptr.domainName),
          )) {
            final txt = <String, String>{};
            await for (final t in client.lookup<TxtResourceRecord>(
              ResourceRecordQuery.text(ptr.domainName),
            )) {
              for (final line in t.text.split('\n')) {
                final i = line.indexOf('=');
                if (i > 0) txt[line.substring(0, i)] = line.substring(i + 1);
              }
            }
            await for (final ip in client.lookup<IPAddressResourceRecord>(
              ResourceRecordQuery.addressIPv4(srv.target),
            )) {
              final instance = ptr.domainName.split('.$type').first;
              _add(ip.address.address, type, instance, srv.port, txt);
            }
          }
        }
      }
    } catch (_) {
      // mDNS can be blocked on some networks; manual IP still works.
    } finally {
      client.stop();
    }
  }

  Future<void> stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    await _sub?.cancel();
    _sub = null;
    if (Platform.isAndroid) {
      try {
        await NativeBridge.stopDiscovery();
      } catch (_) {}
    }
    if (scanning) {
      scanning = false;
      notifyListeners();
    }
  }
}
