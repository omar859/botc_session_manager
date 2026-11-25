import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _limitTimer;
  bool _recording = false;
  final ValueNotifier<Duration> elapsed = ValueNotifier(Duration.zero);

  bool get isRecording => _recording;

  Future<bool> start({Future<void> Function()? onLimitReached}) async {
    if (isRecording) return false;
    if (!await _recorder.hasPermission()) return false;
    final directory = await getTemporaryDirectory();
    final file = File(
        '${directory.path}/voice_${DateTime.now().microsecondsSinceEpoch}.m4a');
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 32000,
        sampleRate: 22050,
        numChannels: 1,
      ),
      path: file.path,
    );
    _limitTimer?.cancel();
    elapsed.value = Duration.zero;
    _limitTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final next = elapsed.value + const Duration(seconds: 1);
      elapsed.value = next;
      if (next.inSeconds >= 29) {
        timer.cancel();
        unawaited(onLimitReached?.call());
      }
    });
    _recording = true;
    return true;
  }

  Future<String?> stop() async {
    _limitTimer?.cancel();
    _limitTimer = null;
    final path = await _recorder.stop();
    _recording = false;
    elapsed.value = Duration.zero;
    return path;
  }

  Future<void> cancel() async {
    final path = await stop();
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }

  Future<void> dispose() async {
    _limitTimer?.cancel();
    elapsed.dispose();
    await _recorder.dispose();
  }
}
