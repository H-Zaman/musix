import 'package:flutter/material.dart';
import 'package:musix/providers/youtube_downloader_provider.dart';
import 'package:musix/theme/winamp_theme.dart';
import 'package:provider/provider.dart';

/// Optional fallback backend: only used when downloading on the device fails.
class BackendSettings extends StatefulWidget {
  const BackendSettings({super.key});

  @override
  State<BackendSettings> createState() => _BackendSettingsState();
}

class _BackendSettingsState extends State<BackendSettings> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final downloader = context.read<YoutubeDownloaderProvider>();
    _url = TextEditingController(text: downloader.backendUrl);
    _key = TextEditingController(text: downloader.apiKey);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    super.dispose();
  }

  InputDecoration _decoration(WinampColors colors, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: colors.statusStyle?.copyWith(color: Colors.white24),
        filled: true,
        fillColor: colors.displayBg,
        isDense: true,
        border: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border!),
        ),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: colors.border!),
        ),
      );

  void _save(YoutubeDownloaderProvider downloader) {
    setState(() => _formError = downloader.saveBackend(_url.text, _key.text));
  }

  Future<void> _test(YoutubeDownloaderProvider downloader) async {
    if (_url.text.trim().isEmpty) {
      setState(() => _formError = 'Enter the backend URL to test');
      return;
    }
    final error = downloader.saveBackend(_url.text, _key.text);
    setState(() => _formError = error);
    if (error == null) await downloader.testBackend();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<WinampColors>()!;
    final downloader = context.watch<YoutubeDownloaderProvider>();
    final status = _formError ?? downloader.backendStatus;
    final ok = _formError == null && downloader.backendOk == true;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.panelBg,
        border: Border.all(color: colors.border!, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('FALLBACK BACKEND (OPTIONAL)', style: colors.tickerStyle),
          const SizedBox(height: 4),
          Text(
            'Only used if downloading on this device fails.',
            style: colors.statusStyle?.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            style: colors.statusStyle?.copyWith(color: colors.textGreen),
            decoration: _decoration(colors, 'https://your-backend.example.com'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _key,
            obscureText: true,
            autocorrect: false,
            style: colors.statusStyle?.copyWith(color: colors.textGreen),
            decoration: _decoration(colors, 'API KEY (IF REQUIRED)'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _save(downloader),
                  child: Text('SAVE', style: colors.statusStyle),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: downloader.testingBackend
                      ? null
                      : () => _test(downloader),
                  child: Text(
                    downloader.testingBackend
                        ? 'TESTING...'
                        : 'TEST CONNECTION',
                    style: colors.statusStyle,
                  ),
                ),
              ),
            ],
          ),
          if (status != null) ...[
            const SizedBox(height: 8),
            Text(
              status,
              style: colors.statusStyle?.copyWith(
                color: ok ? colors.textGreen : Colors.redAccent,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
