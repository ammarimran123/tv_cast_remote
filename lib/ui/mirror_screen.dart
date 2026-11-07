import 'dart:io';

import 'package:flutter/material.dart';

import '../app.dart';
import '../services/native_bridge.dart';
import 'widgets.dart';

class MirrorScreen extends StatelessWidget {
  const MirrorScreen({super.key});

  Future<void> _start(BuildContext context) async {
    final opened = await NativeBridge.openScreenCast();
    if (!context.mounted) return;
    final tv = conn.device?.name ?? 'your TV';
    switch (opened) {
      case 'cast' || 'wifi_display':
        toast(context, 'Choose "$tv" in the list to start mirroring.');
      case 'smart_view':
        toast(context, 'Pick "$tv" in Smart View.');
      case 'google_home':
        toast(context, 'In Google Home, open $tv and tap "Cast my screen".');
      default:
        toast(
          context,
          'Open Quick Settings and tap "Screen Cast" / "Smart View".',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final android = Platform.isAndroid;
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [const Color(0xFF6C5CE7), const Color(0xFF00B4D8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                const SizedBox(height: 8),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.smartphone_rounded,
                      color: Colors.white,
                      size: 54,
                    ),
                    SizedBox(width: 10),
                    Icon(Icons.east_rounded, color: Colors.white70, size: 30),
                    SizedBox(width: 10),
                    Icon(Icons.tv_rounded, color: Colors.white, size: 74),
                  ],
                ),
                const SizedBox(height: 18),
                const Text(
                  'Mirror your screen',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  conn.device == null
                      ? 'Show everything on your phone or tablet on the TV — apps, games, photos and presentations.'
                      : 'Show your phone or tablet screen on ${conn.device!.name}.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF3D2FB8),
                    minimumSize: const Size.fromHeight(54),
                  ),
                  onPressed: android ? () => _start(context) : null,
                  icon: const Icon(Icons.screen_share_rounded),
                  label: const Text(
                    'Start mirroring',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          if (!android)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Card(
                child: ListTile(
                  leading: const Icon(Icons.info_outline),
                  title: const Text('Not available on iPhone/iPad'),
                  subtitle: const Text(
                    'iOS only mirrors to AirPlay receivers. Use the Cast tab to send photos and videos instead.',
                  ),
                ),
              ),
            ),
          const SectionTitle('How it works'),
          Card(
            child: Column(
              children: [
                _Step(
                  1,
                  'Same Wi-Fi',
                  'Your phone and TV must be on the same Wi-Fi network.',
                ),
                _Step(
                  2,
                  'Tap Start mirroring',
                  'Your phone\'s built-in Cast screen opens.',
                ),
                _Step(
                  3,
                  'Pick your TV',
                  'Select ${conn.device?.name ?? 'your TV'} and confirm "Start now".',
                ),
                _Step(
                  4,
                  'Stop any time',
                  'Tap the cast icon in your notification shade and choose Disconnect.',
                ),
              ],
            ),
          ),
          const SectionTitle('Tips'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.speed_rounded, color: cs.primary),
                  title: const Text('Smoother mirroring'),
                  subtitle: const Text(
                    'Use 5 GHz Wi-Fi and keep the phone close to the router.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.home_rounded, color: cs.primary),
                  title: const Text('No Cast option on your phone?'),
                  subtitle: const Text(
                    'Google Home → your TV → "Cast my screen" works on almost every Android phone.',
                  ),
                  trailing: android
                      ? TextButton(
                          onPressed: NativeBridge.openGoogleHome,
                          child: const Text('Open'),
                        )
                      : null,
                ),
                ListTile(
                  leading: Icon(Icons.movie_filter_outlined, color: cs.primary),
                  title: const Text('Watching a video?'),
                  subtitle: const Text(
                    'The Cast tab streams files in full quality and lets you use your phone while it plays.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String title;
  final String body;
  const _Step(this.n, this.title, this.body);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        radius: 16,
        backgroundColor: cs.primaryContainer,
        child: Text(
          '$n',
          style: TextStyle(
            color: cs.onPrimaryContainer,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(body),
    );
  }
}
