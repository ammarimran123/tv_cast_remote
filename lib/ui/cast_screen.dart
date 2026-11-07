import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../app.dart';
import '../services/connection_manager.dart';
import '../services/media_server.dart';
import 'widgets.dart';

class CastScreen extends StatefulWidget {
  final VoidCallback onFindDevices;
  const CastScreen({super.key, required this.onFindDevices});

  @override
  State<CastScreen> createState() => _CastScreenState();
}

class _CastScreenState extends State<CastScreen> {
  bool _picking = false;
  double? _dragPos;

  Future<void> _pick(FileType type) async {
    setState(() => _picking = true);
    try {
      final files = await FilePicker.pickFiles(type: type);
      if (files.isEmpty) return;
      final items = <CastItem>[];
      for (final f in files) {
        final path = f.path ?? await _copyToCache(f);
        items.add(
          CastItem(title: f.name, path: path, contentType: mimeFor(f.name)),
        );
      }
      conn.setQueue(items);
      await _play(0);
    } catch (e) {
      if (mounted) toast(context, 'Could not open the file: $e');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<String> _copyToCache(PlatformFile f) async {
    final dir = await getTemporaryDirectory();
    final out = File(
      '${dir.path}/cast_${DateTime.now().millisecondsSinceEpoch}_${f.name}',
    );
    final sink = out.openWrite();
    await sink.addStream(f.readAsByteStream());
    await sink.close();
    return out.path;
  }

  Future<void> _play(int index) async {
    final err = await conn.playIndex(index);
    if (err != null && mounted) toast(context, err);
  }

  Future<void> _castLink() async {
    final c = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cast a link'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Paste a direct video, audio or image link (MP4, M3U8, MP3, JPG…). '
              'YouTube links open in the YouTube app on the TV.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(hintText: 'https://…'),
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
            child: const Text('Cast'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
      if (mounted) toast(context, 'Enter a full http(s) link.');
      return;
    }
    final host = uri.host.toLowerCase();
    if (host.contains('youtube.com') ||
        host.contains('youtu.be') ||
        host.contains('netflix.com')) {
      if (conn.remoteReady) {
        conn.openLink(url);
        if (mounted) toast(context, 'Opening on the TV…');
      } else if (mounted) {
        toast(context, 'Pair the TV remote to open YouTube/Netflix links.');
      }
      return;
    }
    final name = uri.pathSegments.isEmpty ? url : uri.pathSegments.last;
    conn.setQueue([
      CastItem(title: name, url: url, contentType: mimeFor(name)),
    ]);
    await _play(0);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: conn,
      builder: (context, _) {
        if (conn.device == null || conn.state == LinkState.disconnected) {
          return NotConnectedView(
            message: 'Connect to a TV to cast photos, videos and music from this phone.',
            onFindDevices: widget.onFindDevices,
          );
        }
        final busy = _picking || conn.castBusy;
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
          children: [
            if (busy) const LinearProgressIndicator(),
            if (conn.nowPlaying != null)
              _NowPlaying(
                dragPos: _dragPos,
                onDrag: (v) => setState(() => _dragPos = v),
                onDragEnd: (v) {
                  conn.cast?.seek(v);
                  setState(() => _dragPos = null);
                },
              ),
            const SectionTitle('Cast from this phone'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.25,
              children: [
                _SourceCard(
                  icon: Icons.photo_library_rounded,
                  title: 'Photos',
                  subtitle: 'Show pictures on TV',
                  color: const Color(0xFFFF8A3D),
                  onTap: busy ? null : () => _pick(FileType.image),
                ),
                _SourceCard(
                  icon: Icons.video_library_rounded,
                  title: 'Videos',
                  subtitle: 'Play phone videos',
                  color: const Color(0xFF6C5CE7),
                  onTap: busy ? null : () => _pick(FileType.video),
                ),
                _SourceCard(
                  icon: Icons.library_music_rounded,
                  title: 'Music',
                  subtitle: 'Play audio files',
                  color: const Color(0xFF00B894),
                  onTap: busy ? null : () => _pick(FileType.audio),
                ),
                _SourceCard(
                  icon: Icons.link_rounded,
                  title: 'Web link',
                  subtitle: 'MP4, M3U8, YouTube',
                  color: const Color(0xFF0984E3),
                  onTap: busy ? null : _castLink,
                ),
              ],
            ),
            if (conn.queue.length > 1) ...[
              SectionTitle('Queue · ${conn.queue.length} items'),
              Card(
                child: Column(
                  children: [
                    for (var i = 0; i < conn.queue.length; i++)
                      ListTile(
                        leading: Icon(
                          conn.queue[i].isImage
                              ? Icons.image_outlined
                              : conn.queue[i].isAudio
                              ? Icons.music_note_outlined
                              : Icons.movie_outlined,
                        ),
                        title: Text(
                          conn.queue[i].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: i == conn.queueIndex
                            ? Icon(
                                Icons.equalizer_rounded,
                                color: Theme.of(context).colorScheme.primary,
                              )
                            : null,
                        onTap: busy ? null : () => _play(i),
                      ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              'Media plays through Chromecast built-in on your TV. Keep this app open while '
              'casting files from your phone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;
  const _SourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NowPlaying extends StatelessWidget {
  final double? dragPos;
  final ValueChanged<double> onDrag;
  final ValueChanged<double> onDragEnd;
  const _NowPlaying({
    required this.dragPos,
    required this.onDrag,
    required this.onDragEnd,
  });

  static String _fmt(double s) {
    final d = Duration(seconds: s.round());
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(h > 0 ? 2 : 1, '0');
    final sec = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final item = conn.nowPlaying!;
    final media = conn.media;
    final cast = conn.cast;
    final duration = media?.duration ?? 0;
    final pos = dragPos ?? media?.position ?? 0;
    final playing = media?.isPlaying ?? false;
    final state = media?.playerState ?? 'LOADING';

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [cs.primaryContainer, cs.tertiaryContainer],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.cast_connected_rounded, color: cs.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Casting to ${conn.device?.name}',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                state,
                style: TextStyle(
                  color: cs.onPrimaryContainer,
                  fontSize: 11,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            item.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: cs.onPrimaryContainer,
            ),
          ),
          if (!item.isImage && duration > 0) ...[
            Slider(
              value: pos.clamp(0, duration).toDouble(),
              max: duration,
              onChanged: onDrag,
              onChangeEnd: onDragEnd,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    _fmt(pos),
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _fmt(duration),
                    style: TextStyle(
                      color: cs.onPrimaryContainer,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ] else
            const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                iconSize: 30,
                onPressed: conn.queueIndex > 0 ? conn.previous : null,
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              if (!item.isImage)
                IconButton(
                  iconSize: 30,
                  onPressed: () => cast?.seek(
                    (pos - 10).clamp(0, double.infinity).toDouble(),
                  ),
                  icon: const Icon(Icons.replay_10_rounded),
                ),
              IconButton.filled(
                iconSize: 38,
                onPressed: item.isImage
                    ? null
                    : () => playing ? cast?.pause() : cast?.play(),
                icon: Icon(
                  playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              if (!item.isImage)
                IconButton(
                  iconSize: 30,
                  onPressed: () => cast?.seek(pos + 30),
                  icon: const Icon(Icons.forward_30_rounded),
                ),
              IconButton(
                iconSize: 30,
                onPressed: conn.queueIndex < conn.queue.length - 1
                    ? conn.next
                    : null,
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
          Row(
            children: [
              IconButton(
                onPressed: () => cast?.setMuted(!(cast.muted)),
                icon: Icon(
                  (cast?.muted ?? false)
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded,
                ),
              ),
              Expanded(
                child: Slider(
                  value: (cast?.volume ?? 1).clamp(0, 1).toDouble(),
                  onChanged: (v) => cast?.setVolume(v),
                ),
              ),
              TextButton.icon(
                onPressed: conn.stopCasting,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
