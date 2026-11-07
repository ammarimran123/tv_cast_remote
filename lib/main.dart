import 'package:flutter/material.dart';

import 'app.dart';
import 'services/connection_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await store.load();
  conn = ConnectionManager(store);
  runApp(const TvCastApp());

  // Reconnect to the last TV automatically.
  final last = store.lastDevice;
  if (store.autoConnect && last != null) {
    conn.connect(last);
  }
}
