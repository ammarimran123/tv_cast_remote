// Debug client for the Android TV Remote protocol.
//   dart run tool/atv_debug.dart <host> <stateDir>
// Pairs if needed (writes <stateDir>/WAITING_CODE, reads the code from
// <stateDir>/code), then logs every message and executes commands appended
// to <stateDir>/cmd ("text hello", "key 29", "raw <hex>").
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:tv_cast_remote/protocol/atv_pairing.dart';
import 'package:tv_cast_remote/protocol/atv_remote.dart';
import 'package:tv_cast_remote/protocol/der.dart';
import 'package:tv_cast_remote/protocol/proto.dart';

String dump(ProtoMessage m, [int depth = 0]) {
  final parts = <String>[];
  m.fields.forEach((k, vs) {
    for (final v in vs) {
      if (v is int) {
        parts.add('$k:$v');
      } else if (v is Uint8List) {
        String inner;
        try {
          if (depth > 6 || v.isEmpty) throw const FormatException();
          final sub = ProtoMessage.decode(v);
          inner = '{${dump(sub, depth + 1)}}';
          final asText = utf8.decode(v, allowMalformed: true);
          if (RegExp(r'^[\x20-\x7e]+$').hasMatch(asText) && v.length > 1) {
            inner = '"$asText"';
          }
        } catch (_) {
          inner = '"${utf8.decode(v, allowMalformed: true)}"';
        }
        parts.add('$k:$inner');
      }
    }
  });
  return parts.join(' ');
}

Future<void> main(List<String> args) async {
  final host = args[0];
  final dir = Directory(args[1])..createSync(recursive: true);
  final certF = File('${dir.path}/cert.pem');
  final keyF = File('${dir.path}/key.pem');
  ClientIdentity id;
  if (certF.existsSync()) {
    id = ClientIdentity.fromPems(
      certF.readAsStringSync(),
      keyF.readAsStringSync(),
    );
  } else {
    id = ClientIdentity.generate();
    certF.writeAsStringSync(id.certPem);
    keyF.writeAsStringSync(id.keyPem);
  }
  void log(String s) =>
      print('${DateTime.now().toIso8601String().substring(11, 23)} $s');

  final remote = AtvRemote(host, id);
  remote.onRawMessage = (m) {
    if (m.has(8) || m.has(9)) return; // pings
    log('<< ${dump(m)}');
  };
  try {
    await remote.connect();
  } on AtvNotPairedException {
    log('Not paired, starting pairing');
    final p = AtvPairing(host, id);
    await p.start();
    final codeF = File('${dir.path}/code');
    if (codeF.existsSync()) codeF.deleteSync();
    File('${dir.path}/WAITING_CODE').writeAsStringSync('1');
    log('WAITING FOR CODE');
    while (!codeF.existsSync()) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    await p.finish(codeF.readAsStringSync().trim());
    await p.close();
    File('${dir.path}/WAITING_CODE').deleteSync();
    log('Paired');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await remote.connect();
  }
  log('CONNECTED');
  remote.onDisconnected = () {
    log('DISCONNECTED');
    exit(1);
  };

  final cmdF = File('${dir.path}/cmd')..writeAsStringSync('');
  var consumed = 0;
  Timer.periodic(const Duration(milliseconds: 300), (_) {
    final lines = cmdF.readAsLinesSync();
    for (final line in lines.skip(consumed)) {
      log('>> $line');
      final sp = line.indexOf(' ');
      final cmd = sp < 0 ? line : line.substring(0, sp);
      final arg = sp < 0 ? '' : line.substring(sp + 1);
      switch (cmd) {
        case 'text':
          remote.sendText(arg);
        case 'key':
          remote.sendKey(int.parse(arg));
        case 'link':
          remote.launchApp(arg);
        case 'ime':
          // ime <imeCounter> <fieldCounter> <text>
          final p = arg.split(' ');
          remote.debugSendIme(
            int.parse(p[0]),
            int.parse(p[1]),
            p.sublist(2).join(' '),
          );
        case 'keyd':
          // keyd <code> <direction>
          final p = arg.split(' ');
          remote.sendKey(int.parse(p[0]), direction: int.parse(p[1]));
        case 'vbegin':
          // vbegin [sessionId] -> RemoteMessage.remote_voice_begin (30)
          final w = ProtoWriter();
          if (arg.isNotEmpty) w.int32(1, int.parse(arg));
          remote.debugSend(ProtoWriter()..message(30, w));
        case 'vend':
          remote.debugSend(
            ProtoWriter()..message(32, ProtoWriter()..int32(1, int.parse(arg))),
          );
        case 'vfile':
          // vfile <sessionId> <pcmFile> : 16-bit mono PCM, sent in chunks
          final p = arg.split(' ');
          final sid = int.parse(p[0]);
          final bytes = File(p[1]).readAsBytesSync();
          const chunk = 8192; // 256 ms of 8 kHz 16-bit mono
          () async {
            for (var i = 0; i < bytes.length; i += chunk) {
              final end = i + chunk > bytes.length ? bytes.length : i + chunk;
              final piece = Uint8List(chunk)
                ..setRange(0, end - i, bytes.sublist(i, end));
              remote.debugSend(
                ProtoWriter()..message(
                  31,
                  ProtoWriter()
                    ..int32(1, sid)
                    ..bytes(2, piece),
                ),
              );
              await Future<void>.delayed(const Duration(milliseconds: 256));
            }
            remote.debugSend(
              ProtoWriter()..message(32, ProtoWriter()..int32(1, sid)),
            );
            log('audio sent (${bytes.length} bytes)');
          }();
        case 'voice':
          // voice <pcmFile> [realtime]: full flow through the AtvRemote API
          final p = arg.split(' ');
          final pcm = File(p[0]).readAsBytesSync();
          final realtime = p.length > 1;
          () async {
            try {
              final sid = await remote.startVoice();
              log('voice session $sid');
              if (realtime) {
                const c = 8192; // 512 ms
                for (var i = 0; i < pcm.length; i += c) {
                  remote.sendVoice(
                    pcm.sublist(i, i + c > pcm.length ? pcm.length : i + c),
                  );
                  await Future<void>.delayed(const Duration(milliseconds: 512));
                }
              } else {
                remote.sendVoice(pcm);
              }
              await Future<void>.delayed(const Duration(milliseconds: 300));
              remote.endVoice();
              log('voice done');
            } catch (e) {
              log('voice error $e');
            }
          }();
        case 'quit':
          exit(0);
      }
    }
    consumed = lines.length;
  });
}
