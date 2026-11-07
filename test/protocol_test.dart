import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tv_cast_remote/protocol/atv_pairing.dart';
import 'package:tv_cast_remote/protocol/atv_remote.dart';
import 'package:tv_cast_remote/protocol/der.dart';
import 'package:tv_cast_remote/protocol/key_codes.dart';
import 'package:tv_cast_remote/protocol/proto.dart';
import 'package:tv_cast_remote/services/media_server.dart';

/// Fake Android TV: TLS server that requests the client certificate.
Future<SecureServerSocket> fakeTv(
  ClientIdentity server,
  ClientIdentity client,
) {
  final ctx = SecurityContext()
    ..useCertificateChainBytes(utf8.encode(server.certPem))
    ..usePrivateKeyBytes(utf8.encode(server.keyPem))
    ..setTrustedCertificatesBytes(utf8.encode(client.certPem));
  return SecureServerSocket.bind(
    InternetAddress.loopbackIPv4,
    0,
    ctx,
    requestClientCertificate: true,
  );
}

Uint8List reply(int status, ProtoWriter body) => varintFramed(
  Uint8List.fromList([
    ...(ProtoWriter()
          ..int32(1, 2)
          ..int32(2, status))
        .toBytes(),
    ...body.toBytes(),
  ]),
);

void main() {
  late ClientIdentity client;
  late ClientIdentity tv;

  setUpAll(() {
    client = ClientIdentity.generate();
    tv = ClientIdentity.generate(commonName: 'fake-tv');
  });

  test('protobuf round trip', () {
    final w = ProtoWriter()
      ..int32(1, 300)
      ..string(2, 'hello')
      ..message(3, ProtoWriter()..boolean(1, true))
      ..int32(4, -1);
    final m = ProtoMessage.decode(w.toBytes());
    expect(m.intField(1), 300);
    expect(m.stringField(2), 'hello');
    expect(m.message(3)!.boolField(1), isTrue);
    final frames = VarintFrameDecoder().add([
      ...varintFramed(w.toBytes()),
      ...varintFramed(w.toBytes()),
    ]);
    expect(frames, hasLength(2));
  });

  test('generated identity reloads from PEM', () {
    final again = ClientIdentity.fromPems(client.certPem, client.keyPem);
    expect(again.modulus, client.modulus);
    expect(again.exponent, BigInt.from(65537));
    expect(client.modulus.bitLength, 2048);
  });

  test('pairing against fake TV with correct and wrong code', () async {
    // Pick a code whose checksum byte is valid for this key pair.
    String? code;
    for (var i = 0; i < 0x10000 && code == null; i++) {
      final tail = i.toRadixString(16).padLeft(4, '0').toUpperCase();
      for (var head = 0; head < 256; head++) {
        final c =
            '${head.toRadixString(16).padLeft(2, '0').toUpperCase()}$tail';
        if (pairingSecret(
              clientModulus: client.modulus,
              clientExponent: client.exponent,
              serverModulus: tv.modulus,
              serverExponent: tv.exponent,
              code: c,
            ) !=
            null) {
          code = c;
          break;
        }
      }
    }
    expect(code, isNotNull);

    final server = await fakeTv(tv, client);
    final gotSecret = Completer<bool>();
    server.listen((s) {
      final dec = VarintFrameDecoder();
      s.listen((data) {
        for (final f in dec.add(data)) {
          final m = ProtoMessage.decode(f);
          expect(m.intField(1), 2);
          expect(m.intField(2), 200);
          if (m.has(10)) {
            expect(m.message(10)!.stringField(1), 'atvremote');
            s.add(
              reply(
                200,
                ProtoWriter()..message(11, ProtoWriter()..string(1, 'Fake TV')),
              ),
            );
          } else if (m.has(20)) {
            final enc = m.message(20)!.message(1)!;
            expect(enc.intField(1), 3);
            expect(enc.intField(2), 6);
            final options = ProtoWriter()
              ..message(
                1,
                ProtoWriter()
                  ..int32(1, 3)
                  ..int32(2, 6),
              )
              ..int32(3, 1);
            s.add(reply(200, ProtoWriter()..message(20, options)));
          } else if (m.has(30)) {
            s.add(reply(200, ProtoWriter()..message(31, ProtoWriter())));
          } else if (m.has(40)) {
            final secret = m.message(40)!.bytesField(1)!;
            final (cn, ce) = rsaPublicKeyFromCertDer(s.peerCertificate!.der);
            final expected = pairingSecret(
              clientModulus: cn,
              clientExponent: ce,
              serverModulus: tv.modulus,
              serverExponent: tv.exponent,
              code: code!,
            )!;
            final ok = listEquals(secret, expected);
            gotSecret.complete(ok);
            s.add(
              reply(ok ? 200 : 402, ProtoWriter()..message(41, ProtoWriter())),
            );
          }
        }
      });
    });

    final pairing = AtvPairing('127.0.0.1', client, port: server.port);
    await pairing.start();
    // A typo fails the local checksum without contacting the TV.
    final wrong =
        '${((int.parse(code!.substring(0, 2), radix: 16) + 1) % 256).toRadixString(16).padLeft(2, '0')}${code.substring(2)}';
    await expectLater(pairing.finish(wrong), throwsA(isA<PairingException>()));
    await pairing.finish(code);
    expect(await gotSecret.future, isTrue);
    await pairing.close();
    await server.close();
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('remote handshake, ping and key press against fake TV', () async {
    final server = await fakeTv(tv, client);
    final keys = <int>[];
    final typed = <String>[];
    final voice = <String>[];
    final gotKey = Completer<void>();
    var configured = false;
    server.listen((s) {
      final dec = VarintFrameDecoder();
      // TV opens with remote_configure.
      s.add(
        varintFramed(
          (ProtoWriter()..message(
                1,
                ProtoWriter()
                  ..int32(1, 622)
                  ..message(
                    2,
                    ProtoWriter()
                      ..string(1, 'MIBOX4')
                      ..string(2, 'Xiaomi'),
                  ),
              ))
              .toBytes(),
        ),
      );
      s.listen((data) {
        for (final f in dec.add(data)) {
          final m = ProtoMessage.decode(f);
          if (m.has(1)) {
            configured = true;
            s.add(
              varintFramed(
                (ProtoWriter()..message(2, ProtoWriter()..int32(1, 622)))
                    .toBytes(),
              ),
            );
            s.add(
              varintFramed(
                (ProtoWriter()..message(8, ProtoWriter()..int32(1, 7)))
                    .toBytes(),
              ),
            );
            s.add(
              varintFramed(
                (ProtoWriter()..message(
                      50,
                      ProtoWriter()
                        ..int32(6, 100)
                        ..int32(7, 25),
                    ))
                    .toBytes(),
              ),
            );
          } else if (m.has(9)) {
            expect(m.message(9)!.intField(1), 7);
          } else if (m.has(21)) {
            final edit = m.message(21)!;
            final field = edit.message(3)!.message(2)!;
            typed.add(
              '${edit.intField(1)}/${edit.intField(2)}:${field.stringField(3)}',
            );
          } else if (m.has(30)) {
            voice.add('begin ${m.message(30)!.intField(1)}');
          } else if (m.has(31)) {
            final p = m.message(31)!;
            voice.add('audio ${p.intField(1)} ${p.bytesField(2)!.length}');
          } else if (m.has(32)) {
            voice.add('end ${m.message(32)!.intField(1)}');
          } else if (m.has(10) && m.message(10)!.intField(1) == TvKey.search) {
            // Real TVs open a voice session in reply to KEYCODE_SEARCH.
            s.add(
              varintFramed(
                (ProtoWriter()..message(
                      30,
                      ProtoWriter()
                        ..int32(1, 5)
                        ..string(2, 'com.google.android.katniss'),
                    ))
                    .toBytes(),
              ),
            );
          } else if (m.has(10)) {
            keys.add(m.message(10)!.intField(1));
            expect(m.message(10)!.intField(2), KeyDirection.short);
            if (!gotKey.isCompleted) gotKey.complete();
          }
        }
      });
    });

    final remote = AtvRemote('127.0.0.1', client, port: server.port);
    TvVolume? volume;
    String? model;
    remote
      ..onVolume = ((v) => volume = v)
      ..onDeviceInfo = ((m, v) => model = '$v $m');
    await remote.connect();
    expect(configured, isTrue);
    remote.sendKey(TvKey.dpadCenter);
    await gotKey.future.timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(keys, [TvKey.dpadCenter]);
    // Text goes through the IME even when the TV never announced counters.
    remote.sendText('dog');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(typed, ['0/0:dog']);

    // Voice: Search key -> TV opens session -> we ack, stream, end.
    final sid = await remote.startVoice();
    expect(sid, 5);
    remote.sendVoice(List.filled(100, 1)); // padded to 8 KB
    remote.sendVoice(List.filled(30000, 1)); // split at 20 KB
    remote.endVoice();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(voice, [
      'begin 5',
      'audio 5 8192',
      'audio 5 20480',
      'audio 5 9520',
      'end 5',
    ]);
    expect(volume?.level, 25);
    expect(model, 'Xiaomi MIBOX4');
    await remote.close();
    await server.close();
  }, timeout: const Timeout(Duration(minutes: 1)));

  test('unpaired client is reported as not paired', () async {
    final server = await fakeTv(tv, client);
    server.listen((s) => s.destroy()); // real TVs drop unknown certificates
    final remote = AtvRemote('127.0.0.1', client, port: server.port);
    await expectLater(remote.connect(), throwsA(isA<AtvNotPairedException>()));
    await server.close();
  });

  test('media server supports range requests', () async {
    final dir = await Directory.systemTemp.createTemp();
    final f = File('${dir.path}/clip.mp4')
      ..writeAsBytesSync(List.generate(1000, (i) => i % 256));
    final ms = MediaServer();
    final url = await ms.publish(f, '127.0.0.1');
    final uri = Uri.parse(url).replace(host: '127.0.0.1');
    final http = HttpClient();
    final req = await http.getUrl(uri);
    req.headers.set(HttpHeaders.rangeHeader, 'bytes=10-19');
    final res = await req.close();
    expect(res.statusCode, 206);
    expect(res.headers.contentType?.mimeType, 'video/mp4');
    final body = await res.fold<List<int>>([], (a, b) => a..addAll(b));
    expect(body, List.generate(10, (i) => 10 + i));
    http.close();
    await ms.close();
    await dir.delete(recursive: true);
  });
}
