import 'package:flutter/material.dart';

import '../app.dart';
import '../services/connection_manager.dart';
import 'cast_screen.dart';
import 'devices_screen.dart';
import 'mirror_screen.dart';
import 'pairing_dialog.dart';
import 'remote_screen.dart';
import 'settings_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> with WidgetsBindingObserver {
  late int _tab = store.lastDevice == null ? 3 : 0;
  bool _pairingShown = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    conn.addListener(_onConn);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    conn.removeListener(_onConn);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) conn.resume();
  }

  void _onConn() {
    if (conn.state == LinkState.pairing && !_pairingShown) {
      _pairingShown = true;
      showPairingDialog(context).whenComplete(() => _pairingShown = false);
    }
    final err = conn.error;
    if (err != null && err != _lastError && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(err)));
    }
    _lastError = err;
  }

  void goToDevices() => setState(() => _tab = 3);

  @override
  Widget build(BuildContext context) {
    final pages = [
      RemoteScreen(onFindDevices: goToDevices),
      CastScreen(onFindDevices: goToDevices),
      const MirrorScreen(),
      const DevicesScreen(),
    ];
    const titles = ['Remote', 'Cast', 'Mirror', 'Devices'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        actions: [
          _ConnectionChip(onTap: goToDevices),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: IndexedStack(index: _tab, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.settings_remote_outlined),
            selectedIcon: Icon(Icons.settings_remote),
            label: 'Remote',
          ),
          NavigationDestination(
            icon: Icon(Icons.cast_outlined),
            selectedIcon: Icon(Icons.cast_connected),
            label: 'Cast',
          ),
          NavigationDestination(
            icon: Icon(Icons.screen_share_outlined),
            selectedIcon: Icon(Icons.screen_share),
            label: 'Mirror',
          ),
          NavigationDestination(
            icon: Icon(Icons.tv_outlined),
            selectedIcon: Icon(Icons.tv),
            label: 'Devices',
          ),
        ],
      ),
    );
  }
}

class _ConnectionChip extends StatelessWidget {
  final VoidCallback onTap;
  const _ConnectionChip({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) {
        final cs = Theme.of(context).colorScheme;
        final (color, text) = switch (conn.state) {
          LinkState.connected => (
            Colors.greenAccent.shade400,
            conn.device?.name ?? 'Connected',
          ),
          LinkState.connecting ||
          LinkState.preparing => (Colors.amber, 'Connecting…'),
          LinkState.reconnecting => (Colors.amber, 'Reconnecting…'),
          LinkState.pairing => (Colors.lightBlueAccent, 'Pairing…'),
          LinkState.disconnected => (cs.outline, 'Not connected'),
        };
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 170),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      text,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
