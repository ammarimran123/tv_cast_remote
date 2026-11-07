import 'package:flutter/material.dart';

import '../app.dart';
import 'widgets.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  Future<void> _resetPairing(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reset pairing key?'),
        content: const Text(
          'This creates a new security key. Every TV will need to be paired again with a new code.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await conn.disconnect();
    await store.resetIdentity();
    if (context.mounted) toast(context, 'Pairing key reset.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListenableBuilder(
        listenable: store,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            const SectionTitle('Appearance'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: SegmentedButton<ThemeMode>(
                  segments: const [
                    ButtonSegment(
                      value: ThemeMode.system,
                      label: Text('System'),
                      icon: Icon(Icons.brightness_auto),
                    ),
                    ButtonSegment(
                      value: ThemeMode.light,
                      label: Text('Light'),
                      icon: Icon(Icons.light_mode),
                    ),
                    ButtonSegment(
                      value: ThemeMode.dark,
                      label: Text('Dark'),
                      icon: Icon(Icons.dark_mode),
                    ),
                  ],
                  selected: {store.themeMode},
                  onSelectionChanged: (s) => store.setThemeMode(s.first),
                ),
              ),
            ),
            const SectionTitle('Remote'),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Vibrate on button press'),
                    value: store.haptics,
                    onChanged: store.setHaptics,
                  ),
                  SwitchListTile(
                    title: const Text('Reconnect to last TV on launch'),
                    value: store.autoConnect,
                    onChanged: store.setAutoConnect,
                  ),
                ],
              ),
            ),
            const SectionTitle('Security'),
            Card(
              child: ListTile(
                leading: const Icon(Icons.key_rounded),
                title: const Text('Reset pairing key'),
                subtitle: const Text('Forget pairing with all TVs'),
                onTap: () => _resetPairing(context),
              ),
            ),
            const SectionTitle('About'),
            const Card(
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.info_outline_rounded),
                    title: Text('TV Cast & Remote'),
                    subtitle: Text('Version 1.0.0'),
                  ),
                  ListTile(
                    leading: Icon(Icons.lock_outline_rounded),
                    title: Text('Private by design'),
                    subtitle: Text(
                      'Everything stays on your Wi-Fi. The remote uses an encrypted, paired TLS connection '
                      '(Android TV Remote protocol v2); casting uses Google Cast.',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
