import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class RelayBridge {
  RelayBridge({required this.relayHost, required this.localPort})
      : roomCode = _randomString(10, 'abcdefghjkmnpqrstuvwxyz23456789'),
        hostToken = _randomString(32, 'abcdefghijklmnopqrstuvwxyz0123456789');

  final String relayHost;
  final int localPort;
  final String roomCode;
  final String hostToken;
  final ValueNotifier<bool> connected = ValueNotifier(false);
  String get joinUrl => 'https://$relayHost/play/$roomCode';

  bool _running = false;
  int _backoffSeconds = 1;
  WebSocketChannel? _relay;
  Timer? _retryTimer;
  Timer? _heartbeatTimer;
  final Map<String, WebSocketChannel> _proxies = {};

  void start() {
    if (_running) return;
    _running = true;
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      for (final proxy in _proxies.values) {
        proxy.sink.add('{"type":"heartbeat"}');
      }
    });
    _connect();
  }

  void stop() {
    _running = false;
    _retryTimer?.cancel();
    _heartbeatTimer?.cancel();
    _closeAllProxies();
    unawaited(_relay?.sink.close() ?? Future<void>.value());
    _relay = null;
    connected.value = false;
  }

  void _connect() {
    if (!_running) return;
    final channel = IOWebSocketChannel.connect(
        Uri.parse('wss://$relayHost/ws/host?room=$roomCode&token=$hostToken'));
    _relay = channel;
    channel.ready.then((_) {
      if (identical(_relay, channel)) {
        connected.value = true;
        _backoffSeconds = 1;
      }
    }, onError: (_) {});
    channel.stream.listen(_onRelayMessage,
        onDone: () => _relayDown(channel),
        onError: (_) => _relayDown(channel),
        cancelOnError: true);
  }

  void _relayDown(WebSocketChannel channel) {
    if (!identical(_relay, channel)) return;
    _relay = null;
    connected.value = false;
    _closeAllProxies();
    if (!_running) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(Duration(seconds: _backoffSeconds), _connect);
    _backoffSeconds = min(_backoffSeconds * 2, 15);
  }

  void _onRelayMessage(dynamic data) {
    if (data is! String) return;
    Map<String, dynamic> message;
    try {
      message = Map<String, dynamic>.from(jsonDecode(data) as Map);
    } catch (_) {
      return;
    }
    final id = message['c'];
    if (id is! String) return;
    switch (message['t']) {
      case 'open':
        {
          _openProxy(id);
          break;
        }
      case 'msg':
        {
          if (message['d'] is String) _proxies[id]?.sink.add(message['d']);
          break;
        }
      case 'close':
        {
          _closeProxy(id);
          break;
        }
    }
  }

  void _openProxy(String id) {
    _closeProxy(id);
    final proxy =
        IOWebSocketChannel.connect(Uri.parse('ws://127.0.0.1:$localPort'));
    _proxies[id] = proxy;
    proxy.stream.listen((data) async {
      if (data is String) {
        _send({'t': 'to', 'c': id, 'd': await _inlineBrowserIcons(data)});
      }
    },
        onDone: () => _proxyEnded(id, proxy),
        onError: (_) => _proxyEnded(id, proxy),
        cancelOnError: true);
  }

  void _proxyEnded(String id, WebSocketChannel proxy) {
    if (_proxies[id] != proxy) return;
    _proxies.remove(id);
    _send({'t': 'kick', 'c': id});
  }

  void _closeProxy(String id) {
    final proxy = _proxies.remove(id);
    if (proxy != null) unawaited(proxy.sink.close());
  }

  void _closeAllProxies() {
    final proxies = _proxies.values.toList();
    _proxies.clear();
    for (final proxy in proxies) {
      unawaited(proxy.sink.close());
    }
  }

  void _send(Map<String, dynamic> message) {
    if (connected.value) _relay?.sink.add(jsonEncode(message));
  }

  /// Online browsers cannot reach the host phone's local HTTP icon server.
  /// Replace those URLs with cached HTTPS assets served by the Cloudflare
  /// relay, avoiding both mixed-content failures and huge WebSocket payloads.
  Future<String> _inlineBrowserIcons(String raw) async {
    if (!raw.contains('iconUrl')) return raw;
    try {
      final decoded = jsonDecode(raw);
      await _replaceIconUrls(decoded);
      return jsonEncode(decoded);
    } catch (_) {
      return raw;
    }
  }

  Future<void> _replaceIconUrls(dynamic value) async {
    if (value is List) {
      for (final item in value) {
        await _replaceIconUrls(item);
      }
      return;
    }
    if (value is! Map) return;

    final iconUrl = value['iconUrl'];
    if (iconUrl is String && iconUrl.startsWith('http')) {
      final name = Uri.tryParse(iconUrl)?.pathSegments.last;
      if (name != null && name.isNotEmpty) {
        value['iconUrl'] = 'https://$relayHost/icons/$name';
      }
    }
    for (final child in value.values.toList()) {
      await _replaceIconUrls(child);
    }
  }

  static String _randomString(int length, String alphabet) {
    final random = Random.secure();
    return List.generate(
        length, (_) => alphabet[random.nextInt(alphabet.length)]).join();
  }
}
