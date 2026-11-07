import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:pointycastle/digests/sha256.dart';

import 'der.dart';
import 'proto.dart';

class PairingException implements Exception {
  final String message;
  final bool badCode;

  /// True when the code was rejected locally and the TV is still showing it.
  final bool sessionAlive;
  PairingException(
    this.message, {
    this.badCode = false,
    this.sessionAlive = false,
  });
  @override
  String toString() => message;
}

SecurityContext clientContext(ClientIdentity id) => SecurityContext()
  ..useCertificateChainBytes(id.certPem.codeUnits)
  ..usePrivateKeyBytes(id.keyPem.codeUnits);

/// Computes the pairing secret the TV expects for a 6-hex-digit [code].
/// Returns null when the code's checksum byte does not match (typo).
Uint8List? pairingSecret({
  required BigInt clientModulus,
  required BigInt clientExponent,
  required BigInt serverModulus,
  required BigInt serverExponent,
  required String code,
}) {
  final c = code.trim().toUpperCase();
  if (!RegExp(r'^[0-9A-F]{6}$').hasMatch(c)) return null;
  final digest = SHA256Digest();
  final input = BytesBuilder()
    ..add(bigIntToBytes(clientModulus))
    ..add(bigIntToBytes(clientExponent))
    ..add(bigIntToBytes(serverModulus))
    ..add(bigIntToBytes(serverExponent))
    ..add([
      int.parse(c.substring(2, 4), radix: 16),
      int.parse(c.substring(4, 6), radix: 16),
    ]);
  final hash = digest.process(input.toBytes());
  if (hash[0] != int.parse(c.substring(0, 2), radix: 16)) return null;
  return hash;
}

/// Android TV Remote v2 pairing (TLS, port 6467). After [start] the TV shows
/// a 6-character code; pass it to [finish].
class AtvPairing {
  final String host;
  final int port;
  final ClientIdentity identity;
  final String clientName;

  SecureSocket? _socket;
  final _decoder = VarintFrameDecoder();
  final _queue = Queue<ProtoMessage>();
  Completer<void>? _waiter;
  Object? _error;
  bool _closed = false;

  AtvPairing(
    this.host,
    this.identity, {
    this.port = 6467,
    this.clientName = 'TV Cast & Remote',
  });

  static const _statusOk = 200;

  Future<void> start() async {
    _socket = await SecureSocket.connect(
      host,
      port,
      context: clientContext(identity),
      onBadCertificate: (_) => true,
      timeout: const Duration(seconds: 8),
    );
    _socket!.listen(
      (data) {
        for (final f in _decoder.add(data)) {
          _queue.add(ProtoMessage.decode(f));
        }
        _wake();
      },
      onError: (Object e) {
        _error = e;
        _wake();
      },
      onDone: () {
        _closed = true;
        _wake();
      },
    );

    // 1. Pairing request -> ack
    _send(
      ProtoWriter()..message(
        10,
        ProtoWriter()
          ..string(1, 'atvremote')
          ..string(2, clientName),
      ),
    );
    await _expect(11);

    // 2. Options: we input a 6-digit hex code shown on the TV.
    final encoding = ProtoWriter()
      ..int32(1, 3) // HEXADECIMAL
      ..int32(2, 6);
    _send(
      ProtoWriter()..message(
        20,
        ProtoWriter()
          ..message(1, encoding)
          ..int32(3, 1),
      ),
    ); // preferred role: INPUT
    await _expect(20);

    // 3. Configuration -> ack. The TV now displays the code.
    _send(
      ProtoWriter()..message(
        30,
        ProtoWriter()
          ..message(1, encoding)
          ..int32(2, 1),
      ),
    );
    await _expect(31);
  }

  Future<void> finish(String code) async {
    final socket = _socket;
    if (socket == null) throw PairingException('Pairing not started');
    final serverCert = socket.peerCertificate;
    if (serverCert == null) throw PairingException('TV sent no certificate');
    final (sn, se) = rsaPublicKeyFromCertDer(serverCert.der);
    final secret = pairingSecret(
      clientModulus: identity.modulus,
      clientExponent: identity.exponent,
      serverModulus: sn,
      serverExponent: se,
      code: code,
    );
    if (secret == null) {
      throw PairingException(
        'That code is not right. Check the TV and try again.',
        badCode: true,
        sessionAlive: true,
      );
    }
    _send(ProtoWriter()..message(40, ProtoWriter()..bytes(1, secret)));
    await _expect(41);
  }

  void _send(ProtoWriter inner) {
    final msg = ProtoWriter()
      ..int32(1, 2) // protocol version
      ..int32(2, _statusOk);
    final payload = BytesBuilder()
      ..add(msg.toBytes())
      ..add(inner.toBytes());
    _socket!.add(varintFramed(payload.toBytes()));
  }

  void _wake() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  Future<ProtoMessage> _expect(int field) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (true) {
      if (_queue.isNotEmpty) {
        final m = _queue.removeFirst();
        final status = m.intField(2);
        if (status != _statusOk) {
          throw PairingException(
            status == 402
                ? 'The TV rejected the code. Try again.'
                : 'The TV refused pairing (status $status).',
            badCode: status == 402,
          );
        }
        if (m.has(field)) return m;
        continue; // unrelated message
      }
      if (_error != null) throw PairingException('Connection error: $_error');
      if (_closed)
        throw PairingException('The TV closed the pairing connection.');
      final remaining = deadline.difference(DateTime.now());
      if (remaining.isNegative)
        throw PairingException('The TV did not respond.');
      _waiter = Completer<void>();
      await _waiter!.future.timeout(remaining, onTimeout: () {});
    }
  }

  Future<void> close() async {
    try {
      await _socket?.close();
    } catch (_) {}
    _socket?.destroy();
    _socket = null;
  }
}
