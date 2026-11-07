import 'dart:convert';
import 'dart:typed_data';

/// Minimal protobuf (proto3 wire format) encoder/decoder.
///
/// Android TV Remote v2 and Google Cast both speak protobuf. Their schemas are
/// small and stable, so a hand-rolled codec avoids a code-generation step.
class ProtoWriter {
  final BytesBuilder _b = BytesBuilder(copy: false);

  static List<int> encodeVarint(int value) {
    final out = <int>[];
    var v = value;
    if (v < 0) {
      // Negative int32/int64 are encoded as 10-byte two's complement.
      v = v.toUnsigned(64);
    }
    while (true) {
      final byte = v & 0x7f;
      v = v >>> 7;
      if (v == 0) {
        out.add(byte);
        return out;
      }
      out.add(byte | 0x80);
    }
  }

  void _tag(int field, int wireType) =>
      _b.add(encodeVarint((field << 3) | wireType));

  void int32(int field, int value) {
    _tag(field, 0);
    _b.add(encodeVarint(value));
  }

  void boolean(int field, bool value) => int32(field, value ? 1 : 0);

  void bytes(int field, List<int> value) {
    _tag(field, 2);
    _b.add(encodeVarint(value.length));
    _b.add(value);
  }

  void string(int field, String value) => bytes(field, utf8.encode(value));

  /// Writes a nested message. Always written, even when empty, because some
  /// messages are identified purely by the presence of the field.
  void message(int field, ProtoWriter nested) => bytes(field, nested.toBytes());

  Uint8List toBytes() => _b.toBytes();
}

/// Decoded protobuf message: field number -> list of raw values.
/// Varints decode to [int]; length-delimited fields decode to [Uint8List].
class ProtoMessage {
  final Map<int, List<Object>> fields;
  ProtoMessage(this.fields);

  factory ProtoMessage.decode(List<int> data) {
    final fields = <int, List<Object>>{};
    var i = 0;
    int readVarint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (i >= data.length) throw const FormatException('Truncated varint');
        final b = data[i++];
        result |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) return result;
        shift += 7;
        if (shift > 63) throw const FormatException('Varint too long');
      }
    }

    while (i < data.length) {
      final key = readVarint();
      final field = key >> 3;
      final wire = key & 7;
      Object value;
      switch (wire) {
        case 0:
          value = readVarint();
        case 1:
          value = Uint8List.fromList(data.sublist(i, i + 8));
          i += 8;
        case 2:
          final len = readVarint();
          if (i + len > data.length) {
            throw const FormatException('Truncated field');
          }
          value = Uint8List.fromList(data.sublist(i, i + len));
          i += len;
        case 5:
          value = Uint8List.fromList(data.sublist(i, i + 4));
          i += 4;
        default:
          throw FormatException('Unsupported wire type $wire');
      }
      fields.putIfAbsent(field, () => []).add(value);
    }
    return ProtoMessage(fields);
  }

  bool has(int field) => fields.containsKey(field);

  int intField(int field, [int fallback = 0]) {
    final v = fields[field]?.first;
    return v is int ? v : fallback;
  }

  bool boolField(int field) => intField(field) != 0;

  Uint8List? bytesField(int field) {
    final v = fields[field]?.first;
    return v is Uint8List ? v : null;
  }

  String stringField(int field, [String fallback = '']) {
    final v = bytesField(field);
    return v == null ? fallback : utf8.decode(v, allowMalformed: true);
  }

  ProtoMessage? message(int field) {
    final v = bytesField(field);
    return v == null ? null : ProtoMessage.decode(v);
  }

  List<ProtoMessage> messages(int field) => (fields[field] ?? const [])
      .whereType<Uint8List>()
      .map(ProtoMessage.decode)
      .toList();
}

/// Splits a byte stream into varint-length-prefixed frames.
class VarintFrameDecoder {
  final List<int> _buf = [];

  List<Uint8List> add(List<int> chunk) {
    _buf.addAll(chunk);
    final frames = <Uint8List>[];
    while (true) {
      var i = 0;
      var len = 0;
      var shift = 0;
      var complete = false;
      while (i < _buf.length) {
        final b = _buf[i++];
        len |= (b & 0x7f) << shift;
        if (b & 0x80 == 0) {
          complete = true;
          break;
        }
        shift += 7;
      }
      if (!complete || _buf.length - i < len) break;
      frames.add(Uint8List.fromList(_buf.sublist(i, i + len)));
      _buf.removeRange(0, i + len);
    }
    return frames;
  }
}

Uint8List varintFramed(Uint8List payload) {
  final b = BytesBuilder(copy: false)
    ..add(ProtoWriter.encodeVarint(payload.length))
    ..add(payload);
  return b.toBytes();
}
