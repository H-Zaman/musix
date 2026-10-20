import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:musix/providers/youtube_downloader_provider.dart';
import 'package:musix/theme/winamp_theme.dart';
import 'package:musix/widgets/backend_settings.dart';
import 'package:provider/provider.dart';

class YoutubeDownloaderScreen extends StatefulWidget {
  const YoutubeDownloaderScreen({super.key});

  @override
  State<YoutubeDownloaderScreen> createState() =>
      _YoutubeDownloaderScreenState();
}

class _YoutubeDownloaderScreenState extends State<YoutubeDownloaderScreen> {
  final TextEditingController _urlController = TextEditingController();

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _pasteUrl() async {
    final data = await Clipboard.getData('text/plain');
    if (data?.text != null) {
      _urlController.text = data!.text!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final winampColors = Theme.of(context).extension<WinampColors>()!;
    final downloader = Provider.of<YoutubeDownloaderProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('YOUTUBE → MP3'),
        shape: Border(
          bottom: BorderSide(color: winampColors.border!, width: 2),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              _buildInputSection(winampColors, downloader),
              const SizedBox(height: 24),
              if (downloader.state != DownloaderState.idle) ...[
                _buildStatusSection(winampColors, downloader),
                const SizedBox(height: 24),
              ],
              const BackendSettings(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputSection(
    WinampColors colors,
    YoutubeDownloaderProvider downloader,
  ) {
    final bool isLoading =
        downloader.state == DownloaderState.creating ||
        downloader.state == DownloaderState.processing ||
        downloader.state == DownloaderState.downloadingFile;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.panelBg,
        border: Border.all(color: colors.border!, width: 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _urlController,
                  enabled: !isLoading,
                  style: colors.statusStyle?.copyWith(color: colors.textGreen),
                  decoration: InputDecoration(
                    hintText: 'PASTE YOUTUBE URL...',
                    hintStyle: colors.statusStyle?.copyWith(
                      color: Colors.white24,
                    ),
                    filled: true,
                    fillColor: colors.displayBg,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.border!),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: colors.border!),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.content_paste),
                onPressed: isLoading ? null : _pasteUrl,
                tooltip: 'Paste',
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: ElevatedButton(
              onPressed: isLoading
                  ? null
                  : () => downloader.startJob(_urlController.text),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.displayBg,
                side: BorderSide(color: colors.textBlue!, width: 1),
                shape: const RoundedRectangleBorder(),
              ),
              child: Text(
                'DOWNLOAD MP3',
                style: colors.statusStyle?.copyWith(
                  color: colors.textBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusSection(
    WinampColors colors,
    YoutubeDownloaderProvider downloader,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.displayBg,
        border: Border.all(color: colors.border!, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (downloader.currentJob?.title != null) ...[
            Text(
              downloader.currentJob!.title!.toUpperCase(),
              style: colors.tickerStyle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),
          ],
          _buildProgressIndicator(colors, downloader),
          const SizedBox(height: 16),
          if (downloader.state == DownloaderState.failed)
            Text(
              downloader.errorMessage ?? 'ERROR',
              style: colors.statusStyle?.copyWith(color: Colors.redAccent),
            )
          else
            _buildMetricsRow(colors, downloader),
          const SizedBox(height: 16),
          _buildActionButtons(colors, downloader),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(
    WinampColors colors,
    YoutubeDownloaderProvider downloader,
  ) {
    final double progress = (downloader.currentJob?.progress ?? 0) / 100.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              downloader.state == DownloaderState.downloadingFile
                  ? 'SAVING TO DEVICE...'
                  : downloader.currentJob?.statusText ?? 'PROCESSING...',
              style: colors.statusStyle?.copyWith(
                color: colors.textBlue,
                fontSize: 10,
              ),
            ),
            Text(
              '${(progress * 100).toInt()}%',
              style: colors.statusStyle?.copyWith(
                color: colors.textGreen,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: Colors.grey.shade900,
          color: colors.textGreen,
          minHeight: 8,
        ),
      ],
    );
  }

  Widget _buildMetricsRow(
    WinampColors colors,
    YoutubeDownloaderProvider downloader,
  ) {
    if (downloader.state == DownloaderState.completed) {
      return Text(
        '✓ DOWNLOAD COMPLETE',
        style: colors.statusStyle?.copyWith(
          color: colors.textGreen,
          fontWeight: FontWeight.bold,
        ),
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          downloader.currentJob?.speed ?? '-- MiB/S',
          style: colors.statusStyle?.copyWith(fontSize: 10),
        ),
        Text(
          'ETA: ${downloader.currentJob?.eta ?? "--:--"}',
          style: colors.statusStyle?.copyWith(fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildActionButtons(
    WinampColors colors,
    YoutubeDownloaderProvider downloader,
  ) {
    if (downloader.state == DownloaderState.completed) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: downloader.shareFile,
          icon: const Icon(Icons.share),
          label: const Text('SHARE / SAVE MP3'),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.textGreen,
            foregroundColor: Colors.black,
            shape: const RoundedRectangleBorder(),
          ),
        ),
      );
    }

    if (downloader.state != DownloaderState.failed) {
      return SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: downloader.cancelJob,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.redAccent),
            foregroundColor: Colors.redAccent,
            shape: const RoundedRectangleBorder(),
          ),
          child: const Text('CANCEL'),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}
