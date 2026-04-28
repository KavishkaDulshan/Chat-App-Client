import 'dart:convert';
import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
class AudioBubble extends StatefulWidget {
  final String url;
  final bool isMe;
  final int? duration;

  const AudioBubble({
    super.key,
    required this.url,
    required this.isMe,
    this.duration,
  });

  @override
  State<AudioBubble> createState() => _AudioBubbleState();
}

class _AudioBubbleState extends State<AudioBubble> {
  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Initialize with a safe default duration to prevent division by zero or min > max
    if (widget.duration != null && widget.duration! > 0) {
      _totalDuration = Duration(seconds: widget.duration!);
    } else {
      _totalDuration = const Duration(
        seconds: 1,
      ); // Default to 1s to avoid 0.0 max
    }

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlaying = state == PlayerState.playing;
          if (state == PlayerState.completed) {
            _position = Duration.zero;
            _isPlaying = false;
          }
        });
      }
    });

    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted && dur.inSeconds > 0) {
        setState(() => _totalDuration = dur);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      setState(() => _isLoading = true);
      try {
        // Try to play from local cache first, then fall back to network
        final localPath = await _getCachedAudioPath();
        if (localPath != null) {
          await _player.play(DeviceFileSource(localPath));
        } else {
          // Play from network and cache in background
          await _player.play(UrlSource(widget.url));
          _cacheAudioInBackground();
        }
        setState(() => _isLoading = false);
      } catch (e) {
        print("Play Error: $e");
        if (mounted) setState(() => _isLoading = false);
      }
    }
  }

  /// Returns local file path if the audio is already cached, null otherwise.
  Future<String?> _getCachedAudioPath() async {
    if (kIsWeb) return null; // No file cache on web
    try {
      final dir = await getApplicationDocumentsDirectory();
      final fileName = _urlToFileName(widget.url);
      final file = File('${dir.path}/audio_cache/$fileName');
      if (await file.exists()) {
        return file.path;
      }
    } catch (_) {}
    return null;
  }

  /// Downloads and caches the audio file in the background.
  void _cacheAudioInBackground() async {
    if (kIsWeb) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final cacheDir = Directory('${dir.path}/audio_cache');
      if (!await cacheDir.exists()) {
        await cacheDir.create(recursive: true);
      }
      final fileName = _urlToFileName(widget.url);
      final file = File('${cacheDir.path}/$fileName');
      if (await file.exists()) return; // Already cached

      final response = await http.get(Uri.parse(widget.url));
      if (response.statusCode == 200) {
        await file.writeAsBytes(response.bodyBytes);
      }
    } catch (_) {
      // Silently fail — audio still played from network
    }
  }

  /// Convert URL to a safe filename using a simple hash.
  String _urlToFileName(String url) {
    final bytes = utf8.encode(url);
    // Simple hash: take last 32 chars of base64
    final hash = base64Encode(bytes);
    final safeHash = hash.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
    final ext = url.contains('.mp3') ? '.mp3' : '.m4a';
    return '${safeHash.substring(safeHash.length > 32 ? safeHash.length - 32 : 0)}$ext';
  }

  String _formatDuration(Duration d) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = twoDigits(d.inMinutes.remainder(60));
    final seconds = twoDigits(d.inSeconds.remainder(60));
    return "$minutes:$seconds";
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : Colors.black87;
    final subColor = widget.isMe ? Colors.white70 : Colors.grey[600];

    // ✅ SAFER SLIDER LOGIC
    // 1. Convert to doubles
    double currentPos = _position.inSeconds.toDouble();
    double maxDur = _totalDuration.inSeconds.toDouble();

    // 2. Ensure Max is never 0 to prevent division errors (though Slider handles 0 min/max)
    if (maxDur <= 0) maxDur = 1.0;

    // 3. CLAMP the value. Ensure currentPos is never > maxDur
    if (currentPos > maxDur) currentPos = maxDur;
    if (currentPos < 0) currentPos = 0;

    return Container(
      width: 220,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: _isLoading
                ? SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: color,
                      strokeWidth: 2,
                    ),
                  )
                : Icon(
                    _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: color,
                    size: 30,
                  ),
            onPressed: _isLoading ? null : _togglePlay,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                    activeTrackColor: color,
                    inactiveTrackColor: subColor!.withOpacity(0.3),
                    thumbColor: color,
                  ),
                  child: Slider(
                    value: currentPos, // ✅ Use clamped value
                    min: 0.0,
                    max: maxDur, // ✅ Use safe max
                    onChanged: (val) async {
                      final newPos = Duration(seconds: val.toInt());
                      await _player.seek(newPos);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatDuration(_position),
                        style: TextStyle(color: subColor, fontSize: 10),
                      ),
                      Text(
                        _formatDuration(_totalDuration),
                        style: TextStyle(color: subColor, fontSize: 10),
                      ),
                    ],
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
