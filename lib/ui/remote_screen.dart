import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app.dart';
import '../protocol/key_codes.dart';
import '../services/connection_manager.dart';
import 'widgets.dart';

class TvApp {
  final String name;
  final String link;
  final Color color;
  final IconData icon;
  const TvApp(this.name, this.link, this.color, this.icon);
}

const tvApps = [
  TvApp(
    'YouTube',
    'https://www.youtube.com',
    Color(0xFFFF0033),
    Icons.play_arrow_rounded,
  ),
  TvApp(
    'Netflix',
    'market://launch?id=com.netflix.ninja',
    Color(0xFFE50914),
    Icons.movie_rounded,
  ),
  TvApp(
    'Prime Video',
    'https://app.primevideo.com',
    Color(0xFF00A8E1),
    Icons.local_movies_rounded,
  ),
  TvApp(
    'Disney+',
    'https://www.disneyplus.com',
    Color(0xFF113CCF),
    Icons.auto_awesome_rounded,
  ),
  TvApp(
    'Spotify',
    'market://launch?id=com.spotify.tv.android',
    Color(0xFF1DB954),
    Icons.music_note_rounded,
  ),
  TvApp(
    'Play Store',
    'market://launch?id=com.android.vending',
    Color(0xFF01875F),
    Icons.shop_rounded,
  ),
  TvApp(
    'Kodi',
    'market://launch?id=org.xbmc.kodi',
    Color(0xFF17B2E7),
    Icons.live_tv_rounded,
  ),
  TvApp(
    'Settings',
    'market://launch?id=com.android.tv.settings',
    Color(0xFF607D8B),
    Icons.settings_rounded,
  ),
];

class RemoteScreen extends StatefulWidget {
  final VoidCallback onFindDevices;
  const RemoteScreen({super.key, required this.onFindDevices});

  @override
  State<RemoteScreen> createState() => _RemoteScreenState();
}

class _RemoteScreenState extends State<RemoteScreen> {
  bool _touchpad = false;

  void k(int code) => conn.key(code);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) {
        final d = conn.device;
        if (d == null || conn.state == LinkState.disconnected) {
          return NotConnectedView(
            message:
                'Connect to an Android TV on your Wi-Fi to use it as a remote.',
            onFindDevices: widget.onFindDevices,
          );
        }
        if (!d.supportsRemote && conn.state == LinkState.connected) {
          return NotConnectedView(
            message:
                '${d.name} only supports casting. Remote control needs an '
                'Android TV / Google TV device (Mi Box, TV Box S, Chromecast with Google TV).',
            onFindDevices: widget.onFindDevices,
          );
        }
        final ready = conn.remoteReady;
        return AbsorbPointer(
          absorbing: !ready,
          child: AnimatedOpacity(
            opacity: ready ? 1 : 0.45,
            duration: const Duration(milliseconds: 200),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
              children: [
                _statusCard(context),
                const SizedBox(height: 18),
                _topRow(context),
                const SizedBox(height: 22),
                Center(child: _modeToggle()),
                const SizedBox(height: 18),
                Center(
                  child: _touchpad ? _Touchpad(onKey: k) : _DPad(onKey: k),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    RemoteButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onPressed: () => k(TvKey.back),
                    ),
                    RemoteButton(
                      icon: Icons.home_rounded,
                      tooltip: 'Home',
                      onPressed: () => k(TvKey.home),
                    ),
                    RemoteButton(
                      icon: Icons.menu_rounded,
                      tooltip: 'Menu',
                      onPressed: () => k(TvKey.menu),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _rockers(context),
                const SizedBox(height: 22),
                _mediaRow(),
                const SizedBox(height: 8),
                SectionTitle(
                  'Apps',
                  trailing: TextButton(
                    onPressed: _customLink,
                    child: const Text('Open link'),
                  ),
                ),
                _apps(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final vol = conn.volume;
    final app = conn.currentApp;
    final status = switch (conn.state) {
      LinkState.connected => conn.tvOn == false ? 'TV is in standby' : 'Ready',
      LinkState.reconnecting => 'Reconnecting…',
      LinkState.pairing => 'Waiting for pairing code…',
      _ => 'Connecting…',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tv_rounded, color: cs.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conn.device!.name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        app != null ? '$status · ${_prettyApp(app)}' : status,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (vol != null && vol.max > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    vol.muted
                        ? Icons.volume_off_rounded
                        : Icons.volume_up_rounded,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: vol.muted ? 0 : vol.fraction,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '${vol.level}',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _prettyApp(String pkg) {
    const known = {
      'com.google.android.youtube.tv': 'YouTube',
      'com.netflix.ninja': 'Netflix',
      'com.amazon.amazonvideo.livingroom': 'Prime Video',
      'com.disney.disneyplus': 'Disney+',
      'com.spotify.tv.android': 'Spotify',
      'com.google.android.tvlauncher': 'Home',
      'com.google.android.apps.tv.launcherx': 'Home',
      'com.android.tv.settings': 'Settings',
    };
    return known[pkg] ?? pkg.split('.').last;
  }

  Widget _topRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        RemoteButton(
          icon: Icons.power_settings_new_rounded,
          tooltip: 'Power',
          color: const Color(0xFFE53950),
          foreground: Colors.white,
          onPressed: () => k(TvKey.power),
        ),
        RemoteButton(
          icon: Icons.input_rounded,
          tooltip: 'Input',
          onPressed: () => k(TvKey.tvInput),
        ),
        RemoteButton(
          icon: Icons.keyboard_rounded,
          tooltip: 'Keyboard',
          onPressed: _keyboard,
        ),
        RemoteButton(
          icon: Icons.dialpad_rounded,
          tooltip: 'Number pad',
          onPressed: _numpad,
        ),
        RemoteButton(
          icon: Icons.mic_rounded,
          tooltip: 'Assistant',
          onPressed: () => k(TvKey.assist),
        ),
      ],
    );
  }

  Widget _modeToggle() => SegmentedButton<bool>(
    segments: const [
      ButtonSegment(
        value: false,
        icon: Icon(Icons.gamepad_outlined),
        label: Text('D-pad'),
      ),
      ButtonSegment(
        value: true,
        icon: Icon(Icons.touch_app_outlined),
        label: Text('Touchpad'),
      ),
    ],
    selected: {_touchpad},
    onSelectionChanged: (s) => setState(() => _touchpad = s.first),
  );

  Widget _rockers(BuildContext context) {
    Widget rocker(
      String label,
      IconData up,
      IconData down,
      int upKey,
      int downKey,
    ) {
      final dark = Theme.of(context).brightness == Brightness.dark;
      return Container(
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF232538) : const Color(0xFFECEAF6),
          borderRadius: BorderRadius.circular(34),
        ),
        child: Column(
          children: [
            RemoteButton(
              icon: up,
              repeat: true,
              size: 64,
              color: Colors.transparent,
              onPressed: () => k(upKey),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            RemoteButton(
              icon: down,
              repeat: true,
              size: 64,
              color: Colors.transparent,
              onPressed: () => k(downKey),
            ),
          ],
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        rocker(
          'VOL',
          Icons.add_rounded,
          Icons.remove_rounded,
          TvKey.volumeUp,
          TvKey.volumeDown,
        ),
        Column(
          children: [
            RemoteButton(
              icon: Icons.volume_off_rounded,
              tooltip: 'Mute',
              onPressed: () => k(TvKey.mute),
            ),
            const SizedBox(height: 14),
            RemoteButton(
              icon: Icons.search_rounded,
              tooltip: 'Search',
              onPressed: () => k(TvKey.search),
            ),
            const SizedBox(height: 14),
            RemoteButton(
              icon: Icons.info_outline_rounded,
              tooltip: 'Info',
              onPressed: () => k(TvKey.info),
            ),
          ],
        ),
        rocker(
          'CH',
          Icons.keyboard_arrow_up_rounded,
          Icons.keyboard_arrow_down_rounded,
          TvKey.channelUp,
          TvKey.channelDown,
        ),
      ],
    );
  }

  Widget _mediaRow() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      RemoteButton(
        icon: Icons.skip_previous_rounded,
        size: 52,
        onPressed: () => k(TvKey.previous),
      ),
      RemoteButton(
        icon: Icons.fast_rewind_rounded,
        size: 52,
        repeat: true,
        onPressed: () => k(TvKey.rewind),
      ),
      RemoteButton(
        icon: Icons.play_arrow_rounded,
        size: 64,
        color: Theme.of(context).colorScheme.primary,
        foreground: Theme.of(context).colorScheme.onPrimary,
        tooltip: 'Play / pause',
        onPressed: () => k(TvKey.playPause),
      ),
      RemoteButton(
        icon: Icons.fast_forward_rounded,
        size: 52,
        repeat: true,
        onPressed: () => k(TvKey.fastForward),
      ),
      RemoteButton(
        icon: Icons.skip_next_rounded,
        size: 52,
        onPressed: () => k(TvKey.next),
      ),
    ],
  );

  Widget _apps() => GridView.count(
    crossAxisCount: 4,
    shrinkWrap: true,
    physics: const NeverScrollableScrollPhysics(),
    mainAxisSpacing: 12,
    crossAxisSpacing: 12,
    childAspectRatio: 0.9,
    children: [
      for (final a in tvApps)
        InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () {
            haptic();
            conn.openLink(a.link);
          },
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: a.color,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(a.icon, color: Colors.white, size: 28),
              ),
              const SizedBox(height: 6),
              Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
    ],
  );

  Future<void> _customLink() async {
    final c = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Open on TV'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste a YouTube/Netflix link, or an app package name such as com.plexapp.android.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'https://youtu.be/…'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text.trim()),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    if (link == null || link.isEmpty) return;
    final isPackage =
        RegExp(r'^[a-zA-Z][\w]*(\.[\w]+)+$').hasMatch(link) &&
        !link.contains('/');
    conn.openLink(isPackage ? 'market://launch?id=$link' : link);
  }

  Future<void> _keyboard() async {
    final c = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Type on TV',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Select a text field on the TV first, then type here.',
              style: TextStyle(
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: c,
              autofocus: true,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: 'Search or type text',
              ),
              onSubmitted: (v) {
                conn.text(v);
                k(TvKey.enter);
                c.clear();
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Backspace',
                  onPressed: () => k(TvKey.del),
                  icon: const Icon(Icons.backspace_outlined),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Enter',
                  onPressed: () => k(TvKey.enter),
                  icon: const Icon(Icons.keyboard_return),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    conn.text(c.text);
                    c.clear();
                  },
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('Send'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _numpad() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(32, 0, 32, 20),
          child: GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: 1.6,
            children: [
              for (var i = 1; i <= 9; i++)
                RemoteButton(
                  label: '$i',
                  radius: BorderRadius.circular(18),
                  onPressed: () => k(TvKey.digit(i)),
                ),
              RemoteButton(
                icon: Icons.list_alt_rounded,
                tooltip: 'Guide',
                radius: BorderRadius.circular(18),
                onPressed: () => k(TvKey.guide),
              ),
              RemoteButton(
                label: '0',
                radius: BorderRadius.circular(18),
                onPressed: () => k(TvKey.digit(0)),
              ),
              RemoteButton(
                icon: Icons.subtitles_outlined,
                tooltip: 'Captions',
                radius: BorderRadius.circular(18),
                onPressed: () => k(TvKey.captions),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DPad extends StatelessWidget {
  final void Function(int) onKey;
  const _DPad({required this.onKey});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    const size = 250.0;
    Widget arrow(IconData icon, int code, Alignment a) => Align(
      alignment: a,
      child: RemoteButton(
        icon: icon,
        size: 72,
        repeat: true,
        color: Colors.transparent,
        onPressed: () => onKey(code),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: dark
              ? [const Color(0xFF2A2D44), const Color(0xFF1D1F31)]
              : [const Color(0xFFF1EFFA), const Color(0xFFE2DFF2)],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.18),
            blurRadius: 30,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Stack(
        children: [
          arrow(
            Icons.keyboard_arrow_up_rounded,
            TvKey.dpadUp,
            Alignment.topCenter,
          ),
          arrow(
            Icons.keyboard_arrow_down_rounded,
            TvKey.dpadDown,
            Alignment.bottomCenter,
          ),
          arrow(
            Icons.keyboard_arrow_left_rounded,
            TvKey.dpadLeft,
            Alignment.centerLeft,
          ),
          arrow(
            Icons.keyboard_arrow_right_rounded,
            TvKey.dpadRight,
            Alignment.centerRight,
          ),
          Center(
            child: RemoteButton(
              label: 'OK',
              size: 96,
              color: cs.primary,
              foreground: cs.onPrimary,
              onPressed: () => onKey(TvKey.dpadCenter),
            ),
          ),
        ],
      ),
    );
  }
}

/// Swipe to move focus, tap to select. Mimics the Google TV app's touchpad.
class _Touchpad extends StatefulWidget {
  final void Function(int) onKey;
  const _Touchpad({required this.onKey});

  @override
  State<_Touchpad> createState() => _TouchpadState();
}

class _TouchpadState extends State<_Touchpad> {
  Offset? _dot;

  void _key(int code) {
    haptic();
    widget.onKey(code);
  }

  Drag _onStart(Offset global) {
    final box = context.findRenderObject() as RenderBox;
    setState(() => _dot = box.globalToLocal(global));
    return _PadDrag(
      onKey: _key,
      onMove: (g) => setState(() => _dot = box.globalToLocal(g)),
      onDone: () => setState(() => _dot = null),
      origin: global,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Claims the pointer immediately so swipes never scroll the page.
    return RawGestureDetector(
      gestures: {
        ImmediateMultiDragGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<
              ImmediateMultiDragGestureRecognizer
            >(
              () => ImmediateMultiDragGestureRecognizer(),
              (r) => r.onStart = _onStart,
            ),
      },
      child: Container(
        width: double.infinity,
        height: 250,
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF1D1F31) : const Color(0xFFECEAF6),
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
        ),
        child: Stack(
          children: [
            Center(
              child: Text(
                'Swipe to move · Tap to select\nLong-press for menu',
                textAlign: TextAlign.center,
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
            if (_dot != null)
              Positioned(
                left: _dot!.dx - 22,
                top: _dot!.dy - 22,
                child: IgnorePointer(
                  child: Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: cs.primary.withValues(alpha: 0.35),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PadDrag extends Drag {
  final void Function(int) onKey;
  final void Function(Offset global) onMove;
  final VoidCallback onDone;
  final Offset origin;
  final DateTime _started = DateTime.now();
  Offset _acc = Offset.zero;
  double _travel = 0;
  bool _longFired = false;
  Timer? _longPress;
  static const _step = 42.0;

  _PadDrag({
    required this.onKey,
    required this.onMove,
    required this.onDone,
    required this.origin,
  }) {
    _longPress = Timer(const Duration(milliseconds: 600), () {
      if (_travel < 12) {
        _longFired = true;
        onKey(TvKey.menu);
      }
    });
  }

  @override
  void update(DragUpdateDetails d) {
    onMove(d.globalPosition);
    _travel += d.delta.distance;
    _acc += d.delta;
    while (_acc.dx.abs() >= _step || _acc.dy.abs() >= _step) {
      if (_acc.dx.abs() > _acc.dy.abs()) {
        onKey(_acc.dx > 0 ? TvKey.dpadRight : TvKey.dpadLeft);
        _acc = Offset(_acc.dx - _step * _acc.dx.sign, 0);
      } else {
        onKey(_acc.dy > 0 ? TvKey.dpadDown : TvKey.dpadUp);
        _acc = Offset(0, _acc.dy - _step * _acc.dy.sign);
      }
    }
  }

  @override
  void end(DragEndDetails details) {
    _longPress?.cancel();
    final quick =
        DateTime.now().difference(_started) < const Duration(milliseconds: 450);
    if (!_longFired && quick && _travel < 12) onKey(TvKey.dpadCenter);
    onDone();
  }

  @override
  void cancel() {
    _longPress?.cancel();
    onDone();
  }
}
