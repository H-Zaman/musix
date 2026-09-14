import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:musix/models/audio_meta_data.dart';
import 'package:musix/models/position.dart';
import 'package:provider/provider.dart';
import 'package:musix/providers/playback_provider.dart';
import 'package:musix/theme/winamp_theme.dart';

class MusixPlayerScreen extends StatelessWidget {
  const MusixPlayerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<PlaybackProvider>(context);
    final winampColors = Theme.of(context).extension<WinampColors>()!;

    return Scaffold(
      appBar: AppBar(
        shape: Border(bottom: BorderSide(color: winampColors.border!, width: 2)),
        actions: [
          if (provider.isScanning)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Center(
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: winampColors.textGreen),
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
      drawer: _buildWinampDrawer(context, provider, winampColors),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Column(
            children: [
              // 1. Winamp Main Module (Display Panel)
              _buildMainDisplayModule(context, provider, winampColors),
              const SizedBox(height: 8),
              
              // 2. Winamp Playlist / Component Header Controls
              _buildPlaylistHeaderModule(context, provider, winampColors),
              
              // 3. Winamp List Module
              Expanded(
                child: _buildSongListModule(context, provider, winampColors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainDisplayModule(BuildContext context, PlaybackProvider provider, WinampColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.panelBg,
        border: Border.all(color: colors.border!, width: 2),
      ),
      padding: const EdgeInsets.all(8.0),
      child: Column(
        children: [
          // Branding area logic removed per previous undo instructions
          // Row containing Time display and Status
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Time counter block
              Expanded(
                flex: 4,
                child: StreamBuilder<PositionData>(
                  stream: provider.positionDataStream,
                  builder: (context, snapshot) {
                    final positionData = snapshot.data ?? PositionData(Duration.zero, Duration.zero, Duration.zero);
                    return Container(
                      color: colors.displayBg,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      child: Center(
                        child: Text(
                          _formatDuration(positionData.position),
                          style: colors.displayStyle,
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Track configuration indicators
              Expanded(
                flex: 5,
                child: StreamBuilder<SequenceState?>(
                  stream: provider.player.sequenceStateStream,
                  builder: (context, snapshot) {
                    final state = snapshot.data;
                    final hasTrack = state != null && state.sequence.isNotEmpty;
                    return Container(
                      color: colors.displayBg,
                      padding: const EdgeInsets.all(4.0),
                      height: 46,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            hasTrack ? '320 KBPS' : '000 KBPS',
                            style: colors.statusStyle,
                          ),
                          Text(
                            hasTrack ? '44 KHZ  STEREO' : '-- KHZ  ------',
                            style: colors.statusStyle,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Scrolling Text Display Banner
          StreamBuilder<SequenceState?>(
            stream: provider.player.sequenceStateStream,
            builder: (context, snapshot) {
              final state = snapshot.data;
              final metadata = state?.currentSource?.tag as MediaItem?;
              final titleText = metadata != null
                  ? '${provider.player.currentIndex! + 1}. ${metadata.title}'
                  : '*** WINAMP: SPARKING THE APP ***';
              return Container(
                width: double.infinity,
                color: colors.displayBg,
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                child: Text(
                  titleText.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: colors.tickerStyle,
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          
          // Winamp Slider / Progress tracker bar
          StreamBuilder<PositionData>(
            stream: provider.positionDataStream,
            builder: (context, snapshot) {
              final positionData = snapshot.data ?? PositionData(Duration.zero, Duration.zero, Duration.zero);
              final double maxVal = positionData.duration.inMilliseconds.toDouble();
              final double currVal = positionData.position.inMilliseconds.toDouble().clamp(0.0, maxVal);
              return SizedBox(
                height: 20,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 4,
                    activeTrackColor: colors.textBlue,
                    inactiveTrackColor: Colors.grey.shade900,
                    thumbColor: Colors.white70,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: SliderComponentShape.noOverlay,
                  ),
                  child: Slider(
                    min: 0.0,
                    max: maxVal > 0 ? maxVal : 1.0,
                    value: maxVal > 0 ? currVal : 0.0,
                    onChanged: (v) => provider.player.seek(Duration(milliseconds: v.toInt())),
                  ),
                ),
              );
            },
          ),
          
          // Winamp Core Hardware buttons row
          _buildHardwareButtonRow(provider, colors),
        ],
      ),
    );
  }

  Widget _buildHardwareButtonRow(PlaybackProvider provider, WinampColors colors) {
    final player = provider.player;
    return Padding(
      padding: const EdgeInsets.only(top: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildWinampButton(Icons.skip_previous, () => player.hasPrevious ? player.seekToPrevious() : null, colors),
          
          StreamBuilder<PlayerState>(
            stream: player.playerStateStream,
            builder: (context, snapshot) {
              final playing = snapshot.data?.playing ?? false;
              return Row(
                children: [
                  _buildWinampButton(Icons.play_arrow, !playing ? () => player.play() : null, colors, isActive: playing),
                  const SizedBox(width: 4),
                  _buildWinampButton(Icons.pause, playing ? () => player.pause() : null, colors, isActive: !playing && player.playing),
                ],
              );
            },
          ),
          
          _buildWinampButton(Icons.stop, () {
            player.stop();
            player.seek(Duration.zero);
          }, colors),
          
          _buildWinampButton(Icons.skip_next, () => player.hasNext ? player.seekToNext() : null, colors),
          
          StreamBuilder<bool>(
            stream: player.shuffleModeEnabledStream,
            builder: (context, snapshot) {
              final enabled = snapshot.data ?? false;
              return _buildWinampButton(Icons.shuffle, () => player.setShuffleModeEnabled(!enabled), colors, isActive: enabled);
            },
          ),
          
          StreamBuilder<LoopMode>(
            stream: player.loopModeStream,
            builder: (context, snapshot) {
              final loopMode = snapshot.data ?? LoopMode.off;
              IconData icon = Icons.repeat;
              bool isActive = loopMode != LoopMode.off;
              if (loopMode == LoopMode.one) {
                icon = Icons.repeat_one;
              }
              return _buildWinampButton(
                icon,
                () {
                  final nextMode = loopMode == LoopMode.off 
                      ? LoopMode.all 
                      : (loopMode == LoopMode.all ? LoopMode.one : LoopMode.off);
                  player.setLoopMode(nextMode);
                },
                colors,
                isActive: isActive,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWinampButton(IconData icon, VoidCallback? onTap, WinampColors colors, {bool isActive = false}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isActive ? Colors.grey.shade800 : const Color(0xFF2E2E36),
          border: Border.all(color: isActive ? colors.textGreen! : colors.border!, width: 1),
        ),
        width: 38,
        height: 28,
        child: Icon(
          icon, 
          size: 16, 
          color: onTap == null ? Colors.white24 : (isActive ? colors.textGreen : Colors.white70)
        ),
      ),
    );
  }

  Widget _buildPlaylistHeaderModule(BuildContext context, PlaybackProvider provider, WinampColors colors) {
    return Container(
      color: const Color(0xFF141418),
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'PLAYLIST EDITOR [${provider.allSongs.length} TRACKS]',
            style: colors.statusStyle?.copyWith(fontWeight: FontWeight.bold),
          ),
          IconButton(
            constraints: const BoxConstraints(),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.playlist_add, size: 18, color: Colors.white70),
            onPressed: () => Scaffold.of(context).openDrawer(),
          )
        ],
      ),
    );
  }

  Widget _buildSongListModule(BuildContext context, PlaybackProvider provider, WinampColors colors) {
    if (provider.allSongs.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: colors.displayBg,
          border: Border.all(color: colors.border!, width: 2),
        ),
        child: Center(
          child: Text(
            '--- PLAYLIST EMPTY ---\nUSE UPLOAD TO LOAD TRACKS',
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
      child: StreamBuilder<SequenceState?>(
        stream: provider.player.sequenceStateStream,
        builder: (context, snapshot) {
          final state = snapshot.data;
          final currentIndex = state?.currentIndex;

          return ListView.builder(
            itemCount: provider.allSongs.length,
            itemBuilder: (context, index) {
              final song = provider.allSongs[index];
              final isCurrent = currentIndex == index;

              return InkWell(
                onTap: () => provider.playTrack(song),
                child: Container(
                  color: isCurrent ? const Color(0xFF0A0A20) : Colors.transparent,
                  padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 8.0),
                  child: Row(
                    children: [
                      Text(
                        '${(index + 1).toString().padLeft(2, '0')}. ',
                        style: colors.playlistStyle?.copyWith(
                          color: isCurrent ? colors.textGreen : Colors.white54,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          song.title.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: colors.playlistStyle?.copyWith(
                            color: isCurrent ? colors.textGreen : const Color(0xFFCCCCCC),
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                      IconButton(
                        constraints: const BoxConstraints(),
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.add, size: 14, color: Colors.white30),
                        onPressed: () => _showAddToPlaylistDialog(context, provider, song, colors),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildWinampDrawer(BuildContext context, PlaybackProvider provider, WinampColors colors) {
    return Drawer(
      child: Container(
        color: colors.panelBg,
        child: Column(
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: Color(0xFF050508)),
              child: Center(
                child: Text(
                  'WINAMP PLUGINS\n& PLAYLISTS',
                  textAlign: TextAlign.center,
                  style: colors.statusStyle?.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: colors.textBlue),
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.create_new_folder, color: colors.textGreen),
              title: Text('NEW CUSTOM LIST', style: colors.playlistStyle?.copyWith(color: Colors.white)),
              onTap: () {
                Navigator.pop(context);
                _showCreatePlaylistDialog(context, provider, colors);
              },
            ),
            Divider(color: colors.border),
            Expanded(
              child: ListView.builder(
                itemCount: provider.customPlaylists.length,
                itemBuilder: (context, index) {
                  final playlist = provider.customPlaylists[index];
                  return ListTile(
                    leading: Icon(Icons.queue_music, color: colors.textBlue),
                    title: Text(playlist.name.toUpperCase(), style: colors.playlistStyle?.copyWith(color: Colors.white70)),
                    subtitle: Text('${playlist.trackFilePaths.length} ITEMS', style: colors.playlistStyle?.copyWith(fontSize: 10, color: Colors.white38)),
                    onTap: () {
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context, PlaybackProvider provider, WinampColors colors) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.panelBg,
        title: Text('CREATE PLAYLIST', style: colors.playlistStyle?.copyWith(color: Colors.white)),
        content: TextField(
          controller: controller, 
          style: colors.playlistStyle?.copyWith(color: colors.textGreen),
          decoration: InputDecoration(
            hintText: 'LIST NAME',
            hintStyle: const TextStyle(color: Colors.white24),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.border!)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: colors.textBlue!)),
          )
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('CANCEL', style: colors.playlistStyle?.copyWith(color: Colors.white54))),
          TextButton(
            onPressed: () {
              if (controller.text.isNotEmpty) {
                provider.createPlaylist(controller.text);
                Navigator.pop(context);
              }
            },
            child: Text('OK', style: colors.playlistStyle?.copyWith(color: colors.textGreen)),
          ),
        ],
      ),
    );
  }

  void _showAddToPlaylistDialog(BuildContext context, PlaybackProvider provider, AudioMetadata song, WinampColors colors) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: colors.panelBg,
        title: Text('ADD TO LIST', style: colors.playlistStyle?.copyWith(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: provider.customPlaylists.isEmpty
              ? Text('NO PLAYLISTS AVAILABLE', style: colors.playlistStyle?.copyWith(color: Colors.white38, fontSize: 12))
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: provider.customPlaylists.length,
                  itemBuilder: (context, index) {
                    final playlist = provider.customPlaylists[index];
                    return ListTile(
                      title: Text(playlist.name.toUpperCase(), style: colors.playlistStyle?.copyWith(color: Colors.white70)),
                      onTap: () {
                        provider.addSongToPlaylist(playlist, song);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
