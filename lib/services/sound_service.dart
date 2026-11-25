import 'dart:async';
import 'package:audioplayers/audioplayers.dart';

/// Serializes audio commands. Android MediaPlayer cannot safely receive a
/// stop while an earlier play call is still preparing its source.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _alertPlayer = AudioPlayer();
  final AudioPlayer _nightPlayer = AudioPlayer();
  Future<void> _audioQueue = Future.value();
  Timer? _alertStopTimer;
  bool _alertPlaying = false;
  bool _nightPlaying = false;

  Future<void> _enqueue(Future<void> Function() action) {
    _audioQueue = _audioQueue.then((_) => action()).catchError((_) {});
    return _audioQueue;
  }

  Future<void> playAlert({Duration? duration}) => _enqueue(() async {
        await _stopAlertInternal();
        await _alertPlayer.play(
          AssetSource('sounds/timer_end.mp3'),
          volume: 1.0,
        );
        _alertPlaying = true;
        if (duration != null) {
          _alertStopTimer = Timer(duration, () => stopAlert());
        }
      });

  Future<void> playAlarm() => playAlert();
  Future<void> playAlarmFor(Duration duration) => playAlert(duration: duration);

  /// Plays the optional looping night ambience independently from the timer
  /// alert. A missing asset is ignored so night dimming still works.
  Future<void> playNightAmbience() async {
    if (_nightPlaying) return;
    try {
      await _nightPlayer.setReleaseMode(ReleaseMode.loop);
      await _nightPlayer.play(
        AssetSource('sounds/night.mp3'),
        volume: 0.35,
      );
      _nightPlaying = true;
    } catch (_) {
      _nightPlaying = false;
    }
  }

  Future<void> stopNightAmbience() async {
    if (!_nightPlaying) return;
    try {
      await _nightPlayer.stop();
    } finally {
      _nightPlaying = false;
    }
  }

  Future<void> _stopAlertInternal() async {
    _alertStopTimer?.cancel();
    _alertStopTimer = null;
    if (!_alertPlaying) return;
    await _alertPlayer.stop();
    _alertPlaying = false;
  }

  Future<void> stopAlert() => _enqueue(_stopAlertInternal);
  Future<void> stopAlarm() => stopAlert();

  Future<void> dispose() => _enqueue(() async {
        await _stopAlertInternal();
        await stopNightAmbience();
        await _alertPlayer.dispose();
        await _nightPlayer.dispose();
      });
}
