import 'dart:async';

import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// A small in-process WebSocketChannel retained for relay adapters.
/// HostServer already contains the complete authoritative game protocol; this
/// channel lets that protocol run over a relay without changing hotspot
/// sockets or duplicating the game rules.
class MemoryWebSocketChannel
    with StreamChannelMixin<dynamic>
    implements WebSocketChannel {
  final StreamController<dynamic> _incoming = StreamController<dynamic>();
  final void Function(dynamic data) _onSend;
  late final WebSocketSink _sink = _MemoryWebSocketSink(_onSend, _incoming);
  int? _closeCode;
  String? _closeReason;

  MemoryWebSocketChannel(this._onSend);

  void receive(dynamic data) {
    if (!_incoming.isClosed) _incoming.add(data);
  }

  @override
  Stream<dynamic> get stream => _incoming.stream;

  @override
  WebSocketSink get sink => _sink;

  @override
  Future<void> get ready => Future<void>.value();

  @override
  int? get closeCode => _closeCode;

  @override
  String? get closeReason => _closeReason;

  @override
  String? get protocol => null;

  void closeFromRemote([int? code, String? reason]) {
    _closeCode = code;
    _closeReason = reason;
    if (!_incoming.isClosed) _incoming.close();
  }
}

class _MemoryWebSocketSink implements WebSocketSink {
  final void Function(dynamic data) _onSend;
  final StreamController<dynamic> _incoming;

  _MemoryWebSocketSink(this._onSend, this._incoming);

  @override
  void add(dynamic data) => _onSend(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    _incoming.addError(error, stackTrace);
  }

  @override
  Future<void> addStream(Stream<dynamic> stream) async {
    await for (final data in stream) {
      add(data);
    }
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    if (!_incoming.isClosed) await _incoming.close();
  }

  @override
  Future<void> get done => _incoming.done;
}
