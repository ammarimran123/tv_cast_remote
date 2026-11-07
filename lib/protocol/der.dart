import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Tiny DER (ASN.1) encoder/decoder: just enough to build a self-signed RSA
/// certificate and to read the RSA public key out of the TV's certificate.

Uint8List _len(int n) {
  if (n < 0x80) return Uint8List.fromList([n]);
  final bytes = <int>[];
  var v = n;
  while (v > 0) {
    bytes.insert(0, v & 0xff);
    v >>= 8;
  }
  return Uint8List.fromList([0x80 | bytes.length, ...bytes]);
}

Uint8List derTlv(int tag, List<int> content) =>
    Uint8List.fromList([tag, ..._len(content.length), ...content]);

Uint8List derSeq(List<List<int>> items) =>
    derTlv(0x30, items.expand((e) => e).toList());

Uint8List derSet(List<List<int>> items) =>
    derTlv(0x31, items.expand((e) => e).toList());

Uint8List derNull() => Uint8List.fromList([0x05, 0x00]);

/// Unsigned big-endian bytes of [v] with no leading zeros.
Uint8List bigIntToBytes(BigInt v) {
  if (v == BigInt.zero) return Uint8List.fromList([0]);
  var hex = v.toRadixString(16);
  if (hex.length.isOdd) hex = '0$hex';
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

BigInt bytesToBigInt(List<int> bytes) {
  var r = BigInt.zero;
  for (final b in bytes) {
    r = (r << 8) | BigInt.from(b);
  }
  return r;
}

Uint8List derInt(BigInt v) {
  var b = bigIntToBytes(v);
  if (b[0] & 0x80 != 0) b = Uint8List.fromList([0, ...b]);
  return derTlv(0x02, b);
}

Uint8List derOid(String dotted) {
  final parts = dotted.split('.').map(int.parse).toList();
  final out = <int>[40 * parts[0] + parts[1]];
  for (final p in parts.skip(2)) {
    final chunk = <int>[p & 0x7f];
    var v = p >> 7;
    while (v > 0) {
      chunk.insert(0, (v & 0x7f) | 0x80);
      v >>= 7;
    }
    out.addAll(chunk);
  }
  return derTlv(0x06, out);
}

Uint8List derBitString(List<int> content) => derTlv(0x03, [0, ...content]);

Uint8List derUtcTime(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  final s =
      '${two(u.year % 100)}${two(u.month)}${two(u.day)}${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
  return derTlv(0x17, ascii.encode(s));
}

/// Parsed DER element.
class DerNode {
  final int tag;
  final Uint8List value;
  DerNode(this.tag, this.value);

  bool get constructed => tag & 0x20 != 0;

  List<DerNode> get children {
    final out = <DerNode>[];
    var i = 0;
    while (i < value.length) {
      final (node, next) = DerNode.parseAt(value, i);
      out.add(node);
      i = next;
    }
    return out;
  }

  static (DerNode, int) parseAt(Uint8List data, int offset) {
    var i = offset;
    final tag = data[i++];
    var len = data[i++];
    if (len & 0x80 != 0) {
      final n = len & 0x7f;
      len = 0;
      for (var k = 0; k < n; k++) {
        len = (len << 8) | data[i++];
      }
    }
    return (DerNode(tag, Uint8List.sublistView(data, i, i + len)), i + len);
  }

  static DerNode parse(Uint8List data) => parseAt(data, 0).$1;
}

/// RSA public key (modulus, exponent) from an X.509 certificate in DER form.
(BigInt, BigInt) rsaPublicKeyFromCertDer(Uint8List certDer) {
  final cert = DerNode.parse(certDer);
  final tbs = cert.children.first.children;
  // Optional explicit [0] version tag shifts all following fields by one.
  final offset = tbs.first.tag == 0xa0 ? 1 : 0;
  final spki = tbs[offset + 5];
  final bitString = spki.children[1];
  final rsaKey = DerNode.parse(Uint8List.sublistView(bitString.value, 1));
  final parts = rsaKey.children;
  return (bytesToBigInt(parts[0].value), bytesToBigInt(parts[1].value));
}

String toPem(String label, Uint8List der) {
  final b64 = base64.encode(der);
  final lines = <String>[];
  for (var i = 0; i < b64.length; i += 64) {
    lines.add(b64.substring(i, min(i + 64, b64.length)));
  }
  return '-----BEGIN $label-----\n${lines.join('\n')}\n-----END $label-----\n';
}

Uint8List fromPem(String pem) {
  final body = pem
      .split('\n')
      .where((l) => l.isNotEmpty && !l.startsWith('-----'))
      .join();
  return base64.decode(body);
}

/// A self-signed client identity used to pair with and talk to the TV.
class ClientIdentity {
  final String certPem;
  final String keyPem;
  final BigInt modulus;
  final BigInt exponent;

  ClientIdentity(this.certPem, this.keyPem, this.modulus, this.exponent);

  Map<String, String> toJson() => {'cert': certPem, 'key': keyPem};

  factory ClientIdentity.fromPems(String certPem, String keyPem) {
    final (n, e) = rsaPublicKeyFromCertDer(fromPem(certPem));
    return ClientIdentity(certPem, keyPem, n, e);
  }

  /// Generates a 2048-bit RSA key and self-signed certificate. Slow in pure
  /// Dart (a few seconds), so call it from a background isolate.
  static ClientIdentity generate({String commonName = 'atvremote'}) {
    final seedSource = Random.secure();
    final rnd = FortunaRandom()
      ..seed(
        KeyParameter(
          Uint8List.fromList(List.generate(32, (_) => seedSource.nextInt(256))),
        ),
      );
    final gen = RSAKeyGenerator()
      ..init(
        ParametersWithRandom(
          RSAKeyGeneratorParameters(BigInt.from(65537), 2048, 64),
          rnd,
        ),
      );
    final pair = gen.generateKeyPair();
    final pub = pair.publicKey;
    final priv = pair.privateKey;
    final n = pub.modulus!;
    final e = pub.exponent!;

    final sha256Rsa = derSeq([derOid('1.2.840.113549.1.1.11'), derNull()]);
    final name = derSeq([
      derSet([
        derSeq([derOid('2.5.4.3'), derTlv(0x0c, utf8.encode(commonName))]),
      ]),
    ]);
    final now = DateTime.now().toUtc();
    final spki = derSeq([
      derSeq([derOid('1.2.840.113549.1.1.1'), derNull()]),
      derBitString(derSeq([derInt(n), derInt(e)])),
    ]);
    final serial = BigInt.from(now.millisecondsSinceEpoch);
    final tbs = derSeq([
      derTlv(0xa0, derInt(BigInt.two)), // v3
      derInt(serial),
      sha256Rsa,
      name,
      derSeq([
        derUtcTime(now.subtract(const Duration(days: 1))),
        derUtcTime(now.add(const Duration(days: 3650))),
      ]),
      name,
      spki,
    ]);

    final signer = RSASigner(SHA256Digest(), '0609608648016503040201')
      ..init(true, PrivateKeyParameter<RSAPrivateKey>(priv));
    final sig = signer.generateSignature(tbs).bytes;
    final cert = derSeq([tbs, sha256Rsa, derBitString(sig)]);

    final d = priv.privateExponent!;
    final p = priv.p!;
    final q = priv.q!;
    final pkcs1 = derSeq([
      derInt(BigInt.zero),
      derInt(n),
      derInt(e),
      derInt(d),
      derInt(p),
      derInt(q),
      derInt(d % (p - BigInt.one)),
      derInt(d % (q - BigInt.one)),
      derInt(q.modInverse(p)),
    ]);

    return ClientIdentity(
      toPem('CERTIFICATE', cert),
      toPem('RSA PRIVATE KEY', pkcs1),
      n,
      e,
    );
  }
}
