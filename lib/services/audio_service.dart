// lib/services/audio_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../config.dart';

class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final Dio _dio = Dio();
  String get uploadUrl => '${AppConfig.baseUrl}/upload';

  // Start Recording
  Future<void> startRecording() async {
    try {
      if (await _recorder.hasPermission()) {
        if (kIsWeb) {
          // For Web, we record to memory stream
          await _recorder.start(const RecordConfig(), path: '');
        } else {
          // For Mobile, we need a temp path
          final dir = await getTemporaryDirectory();
          final path =
              '${dir.path}/audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
          await _recorder.start(const RecordConfig(), path: path);
        }
      }
    } catch (e) {
      print("Start Recording Error: $e");
    }
  }

  // Stop Recording -> Returns the Path (Mobile) or Blob (Web)
  Future<String?> stopRecording() async {
    try {
      final path = await _recorder.stop();
      return path;
    } catch (e) {
      print("Stop Recording Error: $e");
      return null;
    }
  }

  // Upload Audio
  Future<String?> uploadAudio(String filePath) async {
    try {
      FormData formData;

      if (kIsWeb) {
        // Web: Fetch the blob from the blob URL and upload bytes
        // Note: 'filePath' on web from 'record' package is a blob URL
        final response = await _dio.get(
          filePath,
          options: Options(responseType: ResponseType.bytes),
        );
        final bytes = response.data;

        formData = FormData.fromMap({
          "file": MultipartFile.fromBytes(bytes, filename: "voice_note.m4a"),
        });
      } else {
        // Mobile: Use file path
        formData = FormData.fromMap({
          "file": await MultipartFile.fromFile(
            filePath,
            filename: "voice_note.m4a",
          ),
        });
      }

      Response response = await _dio.post(uploadUrl, data: formData);

      if (response.statusCode == 200) {
        return response.data['url'];
      }
    } catch (e) {
      print("Audio Upload Error: $e");
    }
    return null;
  }

  Future<void> deleteCachedAudio(String url) async {
    if (kIsWeb) return;
    try {
      final bytes = utf8.encode(url);
      final hash = base64Encode(bytes);
      final safeHash = hash.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '');
      final ext = url.contains('.mp3') ? '.mp3' : '.m4a';
      final fileName =
          '${safeHash.substring(safeHash.length > 32 ? safeHash.length - 32 : 0)}$ext';

      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/audio_cache/$fileName');
      if (await file.exists()) {
        await file.delete();
        print('🗑️ Deleted cached audio: $fileName');
      }
    } catch (e) {
      print("Delete Cached Audio Error: $e");
    }
  }

  void dispose() {
    _recorder.dispose();
  }
}
