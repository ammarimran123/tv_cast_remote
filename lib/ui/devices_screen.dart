import 'package:flutter/material.dart';

import '../app.dart';
import '../models/tv_device.dart';
import '../services/connection_manager.dart';
import 'widgets.dart';

class DevicesScreen extends StatefulWidget {
  const DevicesScreen({super.key});

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  @override
  void initState() {
    super.initState();
    discovery.scan();
  }

  Future<void> _manualConnect() async {
    final ip = TextEditingController();
    final name = TextEditingController();
    final result = await showDialog<TvDevice>(
      context: context,
      builder: (ctx) {
        String? err;
        return StatefulBuilder(
          builder: (ctx, setLocal) => AlertDialog(
            title: const Text('Connect by IP address'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'On the TV open Settings → Network & Internet → your Wi-Fi to find its IP address.',
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: ip,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'IP address',
                    hintText: '192.168.1.25',
                    errorText: err,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name (optional)',
                    hintText: 'Living room TV',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final v = ip.text.trim();
                  final ok =
                      RegExp(r'^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$')
                          .firstMatch(v)
                          ?.groups([1, 2, 3, 4])
                          .every((g) => int.parse(g!) <= 255) ??
                      false;
                  if (!ok) {
                    setLocal(() => err = 'Enter a valid IPv4 address');
                    return;
                  }
                  Navigator.pop(
                    ctx,
                    TvDevice(
                      host: v,
                      name: name.text.trim().isEmpty
                          ? 'TV at $v'
                          : name.text.trim(),
                    ),
                  );
                },
                child: const Text('Connect'),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) {
      final saved = store.saved(result.host);
      if (saved != null && name.text.trim().isEmpty) result.name = saved.name;
      await conn.connect(result);
    }
  }

  Future<void> _deviceMenu(TvDevice d) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                d.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text('${d.displayModel} · ${d.host}'),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename'),
              onTap: () => Navigator.pop(ctx, 'rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Forget this TV'),
              onTap: () => Navigator.pop(ctx, 'forget'),
            ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'forget') {
      if (conn.device?.host == d.host) await conn.disconnect();
      await store.forgetDevice(d.host);
    } else if (action == 'rename') {
      final c = TextEditingController(text: d.name);
      final n = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Rename TV'),
          content: TextField(controller: c, autofocus: true),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, c.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      );
      if (n != null && n.isNotEmpty) {
        d.name = n;
        await store.saveDevice(d);
      }
    }
  }

  /// Discovered device enriched with what we remember (pairing, name).
  TvDevice _withSaved(TvDevice found) {
    final saved = store.saved(found.host);
    if (saved == null) return found;
    final name = saved.name; // keep the user's chosen name
    saved.mergeFrom(found);
    saved.name = name;
    return saved;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([discovery, store, conn]),
      builder: (context, _) {
        final found = discovery.devices;
        final foundHosts = found.map((d) => d.host).toSet();
        final saved = store.savedDevices
            .where((d) => !foundHosts.contains(d.host))
            .toList();
        final cs = Theme.of(context).colorScheme;

        return RefreshIndicator(
          onRefresh: () => discovery.scan(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              _ScanBanner(scanning: discovery.scanning, onScan: discovery.scan),
              SectionTitle(
                'On this network',
                trailing: discovery.scanning
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : null,
              ),
              if (found.isEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          discovery.scanning
                              ? 'Looking for TVs…'
                              : 'No TVs found yet',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '• Turn the TV on and connect it to the same Wi-Fi as this phone.\n'
                          '• Guest networks and some routers block device discovery.\n'
                          '• You can always connect using the TV\'s IP address.',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              for (final d in found) ...[
                _DeviceTile(
                  device: _withSaved(d),
                  online: true,
                  onMenu: _deviceMenu,
                ),
                const SizedBox(height: 10),
              ],
              if (saved.isNotEmpty) ...[
                const SectionTitle('Saved TVs'),
                for (final d in saved) ...[
                  _DeviceTile(device: d, online: false, onMenu: _deviceMenu),
                  const SizedBox(height: 10),
                ],
              ],
              const SizedBox(height: 12),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                onPressed: _manualConnect,
                icon: const Icon(Icons.lan_outlined),
                label: const Text('Connect by IP address'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ScanBanner extends StatelessWidget {
  final bool scanning;
  final VoidCallback onScan;
  const _ScanBanner({required this.scanning, required this.onScan});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF5B4BDB), Color(0xFF0096C7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.wifi_tethering_rounded,
            color: Colors.white,
            size: 40,
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Find TVs on Wi-Fi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Android TV, Mi Box, TV Box S, Chromecast with Google TV',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton.filled(
            style: IconButton.styleFrom(backgroundColor: Colors.white24),
            onPressed: scanning ? null : onScan,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  final TvDevice device;
  final bool online;
  final void Function(TvDevice) onMenu;
  const _DeviceTile({
    required this.device,
    required this.online,
    required this.onMenu,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isCurrent = conn.device?.host == device.host;
    final state = isCurrent ? conn.state : LinkState.disconnected;
    final busy =
        isCurrent &&
        (state == LinkState.connecting ||
            state == LinkState.preparing ||
            state == LinkState.reconnecting);
    final connected = isCurrent && state == LinkState.connected;

    final status = connected
        ? 'Connected'
        : busy
        ? (state == LinkState.preparing
              ? 'Creating secure key…'
              : 'Connecting…')
        : online
        ? (device.paired ? 'Paired · Available' : 'Available')
        : 'Offline · last seen ${_ago(device.lastConnected)}';
    final statusColor = connected
        ? Colors.greenAccent.shade700
        : online
        ? cs.primary
        : cs.outline;

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: connected
            ? BorderSide(color: cs.primary, width: 1.5)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: busy ? null : (connected ? null : () => conn.connect(device)),
        onLongPress: () => onMenu(device),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  device.supportsCast && !device.supportsRemote
                      ? Icons.cast
                      : Icons.tv_rounded,
                  color: cs.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${device.displayModel} · ${device.host}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _Pill(status, statusColor),
                        if (device.supportsRemote)
                          _Pill('Remote', cs.secondary),
                        if (device.supportsCast) _Pill('Cast', cs.tertiary),
                      ],
                    ),
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else if (connected)
                TextButton(
                  onPressed: conn.disconnect,
                  child: const Text('Disconnect'),
                )
              else
                IconButton(
                  onPressed: () => onMenu(device),
                  icon: const Icon(Icons.more_vert_rounded),
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _ago(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill(this.text, this.color);

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
    ),
  );
}
