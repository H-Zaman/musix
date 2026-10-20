import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:musix/models/position.dart';
import 'package:provider/provider.dart';
import 'package:musix/providers/playback_provider.dart';
import 'package:musix/theme/winamp_theme.dart';
import 'package:musix/musix.dart';

class MusixPlayerScreen extends StatefulWidget {
  const MusixPlayerScreen({super.key});

  @override
  State<MusixPlayerScreen> createState() => _MusixPlayerScreenState();
}

class _MusixPlayerScreenState extends State<MusixPlayerScreen> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PlaybackProvider>(context);
    final winampColors = Theme.of(context).extension<WinampColors>()!;

    return Scaffold(
      appBar: AppBar(
        shape: Border(
          bottom: BorderSide(color: winampColors.border!, width: 2),
        ),
        leading: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(Icons.music_note, color: winampColors.textGreen),
        ),
        title: Text(
          'WINAMP',
          style: winampColors.statusStyle?.copyWith(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download, size: 20),
            onPressed: MusixApp.openDownloader,
            tooltip: 'YouTube Downloader',
          ),
          if (provider.isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: winampColors.textGreen,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.file_upload, size: 20),
            onPressed: () => provider.importSongs(),
            tooltip: 'Load Files',
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              _buildMainDisplayModule(context, provider, winampColors),
              const SizedBox(height: 8),
              _buildSearchModule(context, provider, winampColors),
              const SizedBox(height: 8),
              Expanded(
                child: _buildSongListModule(context, provider, winampColors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchModule(
    BuildContext context,
    PlaybackProvider provider,
    WinampColors colors,
  ) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colors.displayBg,
        border: Border.all(color: colors.border!, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(Icons.search, size: 16, color: colors.textBlue),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _searchController,
              onChanged: provider.setSearchQuery,
              style: colors.statusStyle?.copyWith(color: colors.textGreen),
              cursorColor: colors.textBlue,
              decoration: InputDecoration(
                hintText: 'SEARCH TRACK...',
                hintStyle: colors.statusStyle?.copyWith(color: Colors.white24),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: colors.textBlue),
              onPressed: () {
                _searchController.clear();
                provider.setSearchQuery('');
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMainDisplayModule(
    BuildContext context,
    PlaybackProvider provider,
    WinampColors colors,
  ) {
    final hasTrack = provider.currentSong != null;
    final displayIndex = provider.currentDisplayIndex;
    final titleText = hasTrack
        ? '$displayIndex. ${provider.currentSong!.title}'
        : '*** WINAMP: SPARKING THE APP ***';

    return Container(
      decoration: BoxDecoration(
        color: colors.panelBg,
        border: Border.all(color: colors.border!, width: 2),
      ),
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 4,
                child: Column(
                  children: [
                    StreamBuilder<PositionData>(
                      stream: provider.positionDataStream,
                      builder: (context, snapshot) {
                        final positionData =
                            snapshot.data ??
                            PositionData(
                              Duration.zero,
                              Duration.zero,
                              Duration.zero,
                            );
                        return Container(
                          color: colors.displayBg,
                          padding: const EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: Center(
                            child: Text(
                              _formatDuration(positionData.position),
                              style: colors.displayStyle,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      color: colors.displayBg,
                      padding: const EdgeInsets.all(2.0),
                      child: Text(
                        hasTrack ? '320 KBPS / 44 KHZ' : '--- KBPS / -- KHZ',
                        textAlign: TextAlign.center,
                        style: colors.statusStyle?.copyWith(fontSize: 8),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Container(
                  color: colors.displayBg,
                  height: 60,
                  child: WinampEqualizer(
                    isPlaying: provider.isPlaying && hasTrack,
                    fftStream: provider.fftStream,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            color: colors.displayBg,
            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
            child: Text(
              titleText.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: colors.tickerStyle,
            ),
          ),
          const SizedBox(height: 6),
          StreamBuilder<PositionData>(
            stream: provider.positionDataStream,
            builder: (context, snapshot) {
              final positionData =
                  snapshot.data ??
                  PositionData(Duration.zero, Duration.zero, Duration.zero);
              final double maxVal = positionData.duration.inMilliseconds
                  .toDouble();
              final double currVal = positionData.position.inMilliseconds
                  .toDouble()
                  .clamp(0.0, maxVal);
              return SizedBox(
                height: 20,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: colors.textBlue,
                    inactiveTrackColor: Colors.grey.shade900,
                    thumbColor: Colors.white70,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    min: 0.0,
                    max: maxVal > 0 ? maxVal : 1.0,
                    value: maxVal > 0 ? currVal : 0.0,
                    onChanged: (v) =>
                        provider.seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
              );
            },
          ),
          _buildHardwareButtonRow(provider, colors),
        ],
      ),
    );
  }

  Widget _buildHardwareButtonRow(
    PlaybackProvider provider,
    WinampColors colors,
  ) {
    final playing = provider.isPlaying;
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildWinampButton(
            Icons.skip_previous,
            () => provider.previous(),
            colors,
          ),
          Row(
            children: [
              _buildWinampButton(
                Icons.play_arrow,
                !playing ? () => provider.playOrResume() : null,
                colors,
                isActive: playing,
              ),
              const SizedBox(width: 4),
              _buildWinampButton(
                Icons.pause,
                playing ? () => provider.pause() : null,
                colors,
                isActive: false,
              ),
            ],
          ),
          _buildWinampButton(Icons.stop, () => provider.stop(), colors),
          _buildWinampButton(Icons.skip_next, () => provider.next(), colors),
          _buildWinampButton(
            Icons.shuffle,
            () => provider.setShuffleEnabled(!provider.shuffleEnabled),
            colors,
            isActive: provider.shuffleEnabled,
          ),
          _buildWinampButton(
            provider.repeatMode == RepeatMode.one
                ? Icons.repeat_one
                : Icons.repeat,
            () => provider.cycleRepeatMode(),
            colors,
            isActive: provider.repeatMode != RepeatMode.off,
          ),
        ],
      ),
    );
  }

  Widget _buildWinampButton(
    IconData icon,
    VoidCallback? onTap,
    WinampColors colors, {
    bool isActive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? Colors.grey.shade800 : const Color(0xFF2E2E36),
          border: Border.all(
            color: isActive ? colors.textGreen! : colors.border!,
            width: 1,
          ),
        ),
        width: 38,
        height: 28,
        child: Icon(
          icon,
          size: 16,
          color: onTap == null
              ? Colors.white24
              : (isActive ? colors.textGreen : Colors.white70),
        ),
      ),
    );
  }

  Widget _buildSongListModule(
    BuildContext context,
    PlaybackProvider provider,
    WinampColors colors,
  ) {
    if (provider.filteredSongs.isEmpty) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.displayBg,
          border: Border.all(color: colors.border!, width: 2),
        ),
        child: Center(
          child: Text(
            provider.searchQuery.isEmpty
                ? '--- PLAYLIST EMPTY ---\nUSE UPLOAD TO LOAD TRACKS'
                : '--- NO RESULTS FOUND ---',
            textAlign: TextAlign.center,
            style: colors.tickerStyle,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.displayBg,
        border: Border.all(color: colors.border!, width: 2),
      ),
      child: ListView.builder(
        itemCount: provider.filteredSongs.length,
        itemBuilder: (context, index) {
          final song = provider.filteredSongs[index];
          final isPlaying = provider.currentSong?.filePath == song.filePath;

          return Semantics(
            button: true,
            selected: isPlaying,
            label: song.title,
            excludeSemantics: true,
            onTap: () => provider.playTrack(song),
            child: InkWell(
              onTap: () => provider.playTrack(song),
              child: Container(
                color: isPlaying ? const Color(0xFF0A0A20) : Colors.transparent,
                padding: const EdgeInsets.symmetric(
                  vertical: 6.0,
                  horizontal: 8.0,
                ),
                child: Row(
                  children: [
                    Text(
                      '${(index + 1).toString().padLeft(2, '0')}. ',
                      style: colors.playlistStyle?.copyWith(
                        color: isPlaying
                            ? colors.textGreen
                            : colors.textBlue?.withAlpha((0.5 * 255).round()),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        song.title.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: isPlaying
                              ? colors.textGreen
                              : const Color(0xFFCCCCCC),
                          fontFamily: colors.playlistStyle?.fontFamily,
                          fontSize: 12,
                          fontWeight: isPlaying
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ),
                    if (isPlaying)
                      Icon(Icons.equalizer, size: 14, color: colors.textGreen),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class WinampEqualizer extends StatefulWidget {
  final bool isPlaying;
  final Stream<Float32List> fftStream;
  const WinampEqualizer({
    super.key,
    required this.isPlaying,
    required this.fftStream,
  });

  @override
  State<WinampEqualizer> createState() => _WinampEqualizerState();
}

class _WinampEqualizerState extends State<WinampEqualizer> {
  static const int _barCount = 20;
  final List<double> _heights = List.filled(_barCount, 0.0);
  final List<double> _bandBuffer = List.filled(_barCount, 0.0);
  // Bumped per FFT frame; the painter listens to it so only the canvas
  // repaints, not the widget tree.
  final ValueNotifier<int> _frame = ValueNotifier(0);
  late final EqualizerPainter _painter = EqualizerPainter(_heights, _frame);
  StreamSubscription<Float32List>? _sub;

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant WinampEqualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fftStream != widget.fftStream) {
      _sub?.cancel();
      _subscribe();
    }
  }

  void _subscribe() {
    _sub = widget.fftStream.listen((fft) {
      if (!mounted) return;
      if (!widget.isPlaying || fft.isEmpty) {
        if (_heights.any((h) => h > 0.01)) {
          for (int i = 0; i < _barCount; i++) {
            _heights[i] *= 0.8;
          }
          _frame.value++;
        }
        return;
      }
      _fillBands(fft);
      for (int i = 0; i < _barCount; i++) {
        _heights[i] = _heights[i] * 0.4 + _bandBuffer[i] * 0.6;
      }
      _frame.value++;
    });
  }

  // ponytail: fixed 6x gain on raw FFT magnitudes to fill the 0..1 bar
  // range; SoLoud's real output level varies by track, so tune this (or
  // normalize against a running max) if bars run too flat or clip.
  void _fillBands(Float32List fft) {
    final usable = fft.length ~/ 2;
    if (usable == 0) {
      _bandBuffer.fillRange(0, _barCount, 0.0);
      return;
    }
    for (int i = 0; i < _barCount; i++) {
      final start = (i * usable / _barCount).floor();
      final end = ((i + 1) * usable / _barCount).floor().clamp(
        start + 1,
        usable,
      );
      double sum = 0;
      for (int j = start; j < end; j++) {
        sum += fft[j].abs();
      }
      _bandBuffer[i] = ((sum / (end - start)) * 6).clamp(0.0, 1.0);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(painter: _painter, child: Container()),
    );
  }
}

class EqualizerPainter extends CustomPainter {
  final List<double> heights;
  EqualizerPainter(this.heights, Listenable repaint) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final double barWidth = size.width / heights.length;
    final Paint paint = Paint()..style = PaintingStyle.fill;

    for (int i = 0; i < heights.length; i++) {
      final double h = heights[i] * size.height;
      final Rect rect = Rect.fromLTWH(
        i * barWidth + 1,
        size.height - h,
        barWidth - 2,
        h,
      );

      double progress = i / heights.length;
      if (progress < 0.2) {
        paint.color = Colors.greenAccent;
      } else if (progress < 0.4) {
        paint.color = Colors.lightBlueAccent;
      } else if (progress < 0.6) {
        paint.color = Colors.purpleAccent;
      } else if (progress < 0.8) {
        paint.color = Colors.redAccent;
      } else {
        paint.color = Colors.yellowAccent;
      }

      canvas.drawRect(rect, paint);

      paint.color = Colors.white.withValues(alpha: 0.5);
      canvas.drawRect(
        Rect.fromLTWH(i * barWidth + 1, size.height - h - 2, barWidth - 2, 1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant EqualizerPainter oldDelegate) => false; // repaints via the `repaint` listenable
}
