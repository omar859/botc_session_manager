import 'dart:convert';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

class VoiceMessageBubble extends StatefulWidget {
  final String base64Audio;
  final int? durationMs;
  final bool isMine;
  final String? mimeType;

  const VoiceMessageBubble({
    super.key,
    required this.base64Audio,
    required this.durationMs,
    required this.isMine,
    this.mimeType,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  static _VoiceMessageBubbleState? _activeBubble;

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  String? _filePath;

  @override
  void didUpdateWidget(covariant VoiceMessageBubble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.base64Audio != widget.base64Audio) {
      _player.stop();
      _playing = false;
      _filePath = null;
    }
  }

  @override
  void dispose() {
    if (identical(_activeBubble, this)) _activeBubble = null;
    _player.dispose();
    super.dispose();
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (identical(_activeBubble, this)) _activeBubble = null;
    if (mounted) setState(() => _playing = false);
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _stopPlayback();
      return;
    }
    await _activeBubble?._stopPlayback();
    _activeBubble = this;
    final directory = await getTemporaryDirectory();
    final extension = (widget.mimeType ?? '').contains('webm')
        ? 'webm'
        : (widget.mimeType ?? '').contains('ogg')
            ? 'ogg'
            : 'm4a';
    _filePath ??=
        '${directory.path}/chat_voice_${widget.base64Audio.hashCode}.$extension';
    final file = File(_filePath!);
    if (!await file.exists()) {
      await file.writeAsBytes(base64Decode(widget.base64Audio), flush: true);
    }
    await _player.play(DeviceFileSource(file.path));
    if (!mounted) return;
    setState(() => _playing = true);
    _player.onPlayerComplete.first.then((_) {
      if (identical(_activeBubble, this)) _activeBubble = null;
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final seconds = ((widget.durationMs ?? 0) / 1000).ceil();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          color: widget.isMine ? colors.onPrimary : colors.primary,
          onPressed: _toggle,
          tooltip: _playing ? 'Stop voice message' : 'Play voice message',
          icon: Icon(_playing ? Icons.stop : Icons.play_arrow),
        ),
        Text(
          seconds > 0 ? '0:${seconds.toString().padLeft(2, '0')}' : '--:--',
          style: TextStyle(
              color: widget.isMine ? colors.onPrimary : colors.onSurface),
        ),
      ],
    );
  }
}
