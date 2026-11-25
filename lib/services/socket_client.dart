import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../models/message_types.dart';

abstract interface class GameClientTransport {
  bool get isConnected;
  Future<bool> connect({String? reconnectToken});
  void send(Map<String, dynamic> msg);
  void disconnect();
}

class SocketClient implements GameClientTransport {
  WebSocketChannel? _channel;
  final String serverIp;
  final int port;
  final void Function(Map<String, dynamic>) onMessage;
  final void Function()? onDisconnected;
  String? playerId;
  Timer? _pingTimer;

  // FIX: guards against overlapping connect() calls. The old code read
  // the instance field `_channel` three separate times in sequence
  // (assign, await .ready, then .stream.listen) — if a second
  // connect() call fired while the first was still resolving (e.g.
  // the reconnect loop firing again before a slow attempt finished),
  // it could reassign `_channel` mid-flight, so the first call ended
  // up waiting on or listening to the wrong channel. This is the root
  // cause of "shows reconnecting but never actually reconnects."
  bool _connecting = false;

  SocketClient({
    required this.serverIp,
    required this.port,
    required this.onMessage,
    this.onDisconnected,
  });

  @override
  bool get isConnected => _channel != null && _channel!.closeCode == null;

  @override
  Future<bool> connect({String? reconnectToken}) async {
    if (_connecting) return false;
    _connecting = true;
    try {
      final wsUrl = 'ws://$serverIp:$port';
      WebSocketChannel newChannel;
      try {
        newChannel = WebSocketChannel.connect(Uri.parse(wsUrl));
        await newChannel.ready.timeout(const Duration(seconds: 6));
      } catch (e) {
        return false;
      }

      // Only now, once we know THIS attempt actually succeeded, do we
      // touch shared state — using the local `newChannel` throughout
      // instead of re-reading the instance field.
      _pingTimer?.cancel();
      _channel = newChannel;

      newChannel.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            onMessage(msg);
          } catch (_) {}
        },
        onDone: () {
          _pingTimer?.cancel();
          // Only clear/notify if this callback belongs to the
          // currently-active channel — a stale old channel finally
          // closing shouldn't kill a newer, already-working one.
          if (identical(_channel, newChannel)) {
            _channel = null;
            onDisconnected?.call();
          }
        },
        onError: (_) {
          _pingTimer?.cancel();
          if (identical(_channel, newChannel)) {
            _channel = null;
            onDisconnected?.call();
          }
        },
      );

      _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) {
        if (isConnected) {
          newChannel.sink.add(jsonEncode({'type': MessageType.heartbeat}));
        }
      });

      if (reconnectToken != null) {
        newChannel.sink.add(jsonEncode(
            {'type': MessageType.reconnect, 'playerId': reconnectToken}));
      }

      return true;
    } finally {
      _connecting = false;
    }
  }

  @override
  void send(Map<String, dynamic> msg) {
    if (!isConnected) return;
    _channel!.sink.add(jsonEncode(msg));
  }

  @override
  void disconnect() {
    _pingTimer?.cancel();
    if (isConnected) {
      _channel!.sink.close();
    }
    _channel = null;
  }
}
