import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../screens/clock/clock_screen.dart';
import '../screens/pomodoro/pomodoro_screen.dart';
import 'device_api_service.dart';

/// Extends DeviceApiService with feature-specific API calls.
/// Import this file alongside device_api_service.dart to get the full API.
extension ClockApi on DeviceApiService {
  Future<void> sendClockConfig(ClockConfig config) async {
    await postJson('/api/clock/config', {
      'format24h': config.is24h,
      'showDate': config.showDate,
      'showSeconds': config.showSeconds,
      'timezone': config.timezone,
      'ntp': config.ntpServer,
      'brightness': config.brightness,
    });
  }
}

extension PomodoroApi on DeviceApiService {
  Future<void> sendPomodoroConfig(PomodoroConfig config) async {
    await postJson('/api/pomodoro/config', {
      'work': config.workMinutes,
      'shortBreak': config.shortBreakMinutes,
      'longBreak': config.longBreakMinutes,
      'sessions': config.sessionsBeforeLong,
      'brightness': config.brightness,
      'alertOnComplete': config.alertOnComplete,
    });
  }
}

extension GifApi on DeviceApiService {
  Future<List<GifEntry>> fetchGifList() async {
    final res = await getJson('/api/gif/list');
    if (res == null) return [];
    final files = res['files'] as List? ?? [];
    return files.map((f) => GifEntry.fromJson(f as Map<String, dynamic>)).toList();
  }

  Future<bool> uploadGifFile(Uint8List bytes, String filename) async {
    final url = baseUrl;
    if (url == null) return false;
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$url/api/gif/upload'),
      );
      request.files.add(http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
      ));
      final response = await request.send().timeout(const Duration(seconds: 30));
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('uploadGifFile error: $e');
      return false;
    }
  }

  Future<bool> deleteGif(String filename) async {
    try {
      final url = baseUrl;
      if (url == null) return false;
      final res = await http
          .delete(Uri.parse('$url/api/gif/delete'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'file': filename}))
          .timeout(const Duration(seconds: 5));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}

// GIF entry model (used in extension above)
class GifEntry {
  final String filename;
  final int sizeBytes;
  final bool isPlaying;

  const GifEntry({
    required this.filename,
    required this.sizeBytes,
    required this.isPlaying,
  });

  factory GifEntry.fromJson(Map<String, dynamic> j) => GifEntry(
        filename: j['name'] as String? ?? '',
        sizeBytes: j['size'] as int? ?? 0,
        isPlaying: j['playing'] as bool? ?? false,
      );

  String get displayName => filename.replaceAll(RegExp(r'\.gif$', caseSensitive: false), '');

  String get sizeLabel {
    if (sizeBytes < 1024) return '${sizeBytes}B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)}KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)}MB';
  }
}
