import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'socket_client.dart';

class CloudflareRelayClient implements GameClientTransport {
  CloudflareRelayClient({
    required this.relayHost,
    required this.roomCode,
    required this.onMessage,
    this.onDisconnected,
  });

  final String relayHost;
  final String roomCode;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function()? onDisconnected;
  WebSocketChannel? _channel;
  bool _connecting = false;
  Timer? _pingTimer;

  @override
  bool get isConnected => _channel != null && _channel!.closeCode == null;

  @override
  Future<bool> connect({String? reconnectToken}) async {
    if (_connecting || isConnected) return false;
    _connecting = true;
    try {
      final uri = Uri.parse(
        'wss://$relayHost/ws/player?room=${Uri.encodeComponent(roomCode.toLowerCase())}',
      );
      final channel = IOWebSocketChannel.connect(uri);
      try {
        await channel.ready.timeout(const Duration(seconds: 8));
      } catch (_) {
        await channel.sink.close();
        return false;
      }
      _channel = channel;
      channel.stream.listen(
        (data) {
          if (data is! String) return;
          try {
            onMessage(Map<String, dynamic>.from(jsonDecode(data) as Map));
          } catch (_) {}
        },
        onDone: () => _ended(channel),
        onError: (_) => _ended(channel),
        cancelOnError: true,
      );
      _pingTimer?.cancel();
      _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (isConnected) send({'type': 'heartbeat'});
      });
      if (reconnectToken != null) {
        send({'type': 'reconnect', 'playerId': reconnectToken});
      }
      return true;
    } finally {
      _connecting = false;
    }
  }

  void _ended(WebSocketChannel channel) {
    if (!identical(_channel, channel)) return;
    _pingTimer?.cancel();
    _channel = null;
    onDisconnected?.call();
  }

  @override
  void send(Map<String, dynamic> msg) {
    if (isConnected) _channel!.sink.add(jsonEncode(msg));
  }

  @override
  void disconnect() {
    _pingTimer?.cancel();
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.sink.close());
  }
}
