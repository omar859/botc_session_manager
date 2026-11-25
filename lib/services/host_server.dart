import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:shelf_static/shelf_static.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart' as path;
import '../models/message_types.dart';
import '../models/player.dart';
import '../models/private_chat.dart';
import '../models/room_state.dart';
import '../models/script_character.dart';
import 'permissions.dart';
import '../services/character_icons.dart';
import 'memory_web_socket_channel.dart';

class HostServer {
  final Map<String, Set<String>> _pendingOutgoingRequests = {};
  final RoomState room;
  final Map<String, WebSocketChannel> _clients = {};
  final Map<WebSocketChannel, String> _socketToPlayer = {};
  final Map<WebSocketChannel, DateTime> _lastPing = {};
  final Map<String, MemoryWebSocketChannel> _onlineSockets = {};
  HttpServer? _httpServer;
  late String _localIp;
  late int _port;
  final Uuid _uuid = const Uuid();
  final StreamController<Map<String, dynamic>> _eventController =
      StreamController.broadcast();
  Stream<Map<String, dynamic>> get events => _eventController.stream;
  Timer? _pingChecker;
  DateTime? _countdownEndsAt;

  // NEW: lets any device on the same hotspot join as a player from a
  // plain web browser, with no app install — see the '/play' branch in
  // start() below. This is a single self-contained HTML/CSS/JS file
  // (assets/web_client/index.html) that speaks the exact same WebSocket
  // protocol as SocketClient/GameProvider; the WebSocket endpoint itself
  // stays on '/' exactly as before, so the native app is unaffected.
  // Loaded once at start() and served from memory — no temp files needed
  // for this (unlike the script images, which are user-provided and
  // change at runtime).
  String? _webClientHtml;

  Future<void> _loadWebClientHtml() async {
    try {
      _webClientHtml =
          await rootBundle.loadString('assets/web_client/index.html');
    } catch (e) {
      _webClientHtml = null;
    }
  }

  Future<Response> _serveCountdownSound() async {
    try {
      final data = await rootBundle.load('assets/sounds/timer_end.mp3');
      return Response.ok(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        headers: {
          'content-type': 'audio/mpeg',
          'cache-control': 'public, max-age=3600',
        },
      );
    } catch (_) {
      return Response.notFound('Countdown sound not found');
    }
  }

  HostServer(this.room);

  /// Attaches a relay-backed logical client to the same protocol used by
  /// hotspot WebSocket clients. The callback receives JSON strings emitted by
  /// the existing authoritative server logic.
  void connectOnlineClient(
      String connectionId, void Function(String data) onOutgoing) {
    final old = _onlineSockets.remove(connectionId);
    old?.closeFromRemote();
    final socket = MemoryWebSocketChannel((data) => onOutgoing(data as String));
    _onlineSockets[connectionId] = socket;
    _handleConnection(socket);
  }

  void receiveOnlineMessage(String connectionId, Map<String, dynamic> message) {
    _onlineSockets[connectionId]?.receive(jsonEncode(message));
  }

  bool hasOnlineClient(String connectionId) =>
      _onlineSockets.containsKey(connectionId);

  void disconnectOnlineClient(String connectionId) {
    final socket = _onlineSockets.remove(connectionId);
    socket?.closeFromRemote();
  }

  Future<String> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          if (addr.type == InternetAddressType.IPv4 && !addr.isLoopback) {
            final ip = addr.address;
            if (ip.startsWith('192.168.') ||
                ip.startsWith('10.') ||
                ip.startsWith('172.16.') ||
                ip.startsWith('172.17.') ||
                ip.startsWith('172.18.') ||
                ip.startsWith('172.19.') ||
                ip.startsWith('172.20.') ||
                ip.startsWith('172.21.') ||
                ip.startsWith('172.22.') ||
                ip.startsWith('172.23.') ||
                ip.startsWith('172.24.') ||
                ip.startsWith('172.25.') ||
                ip.startsWith('172.26.') ||
                ip.startsWith('172.27.') ||
                ip.startsWith('172.28.') ||
                ip.startsWith('172.29.') ||
                ip.startsWith('172.30.') ||
                ip.startsWith('172.31.')) {
              return ip;
            }
          }
        }
      }
    } catch (_) {
      // A missing or restricted network interface falls back to localhost.
    }
    return '127.0.0.1';
  }

  Future<String> start() async {
    _localIp = await _getLocalIp();
    await _loadWebClientHtml();
    await CharacterIcons.instance.ensureLoaded();

    final scriptDir = Directory('${Directory.systemTemp.path}/botc_scripts');
    if (!scriptDir.existsSync()) scriptDir.createSync(recursive: true);
    final staticHandler = createStaticHandler(scriptDir.path,
        serveFilesOutsidePath: true, defaultDocument: 'index.html');

    final wsHandler = webSocketHandler((WebSocketChannel socket) {
      _handleConnection(socket);
    });

    final cascade = Cascade().add((request) {
      if (request.url.path.startsWith('script/')) {
        final modified = request.change(path: 'script');
        return staticHandler(modified);
      }
      return Response.notFound('Not found');
    }).add((request) {
      final path = request.url.path;
      if (path == 'sounds/timer_end.mp3') {
        return _serveCountdownSound();
      }
      if (path.startsWith('icons/')) {
        return _serveIconAsset(path.substring('icons/'.length));
      }
      return Response.notFound('Not found');
    }).add((request) {
      // NEW: '/play' (and any sub-path under it, in case the page is
      // later split into multiple assets) serves the browser client.
      // Everything else falls through to wsHandler below, unchanged —
      // this is what keeps native app connections working exactly as
      // before, since they upgrade at '/' with no path segment at all.
      final path = request.url.path;
      if (path == 'play' || path.startsWith('play/')) {
        if (_webClientHtml == null) {
          return Response.internalServerError(
            body: 'Browser client is not available on this build.',
          );
        }
        return Response.ok(
          _webClientHtml,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }
      return Response.notFound('Not found');
    }).add(wsHandler);

    _httpServer = await io.serve(cascade.handler, '0.0.0.0', 0);
    _port = _httpServer!.port;
    room.roomCode = 'BOTC-${_uuid.v4().substring(0, 6).toUpperCase()}';

    _pingChecker = Timer.periodic(const Duration(seconds: 5), (_) {
      final now = DateTime.now();
      final toRemove = <WebSocketChannel>[];
      _lastPing.forEach((socket, last) {
        if (now.difference(last).inSeconds > 60) {
          toRemove.add(socket);
        }
      });
      for (final socket in toRemove) {
        _onDisconnect(socket);
      }
    });

    _eventController.add({
      'type': 'server_started',
      'ip': _localIp,
      'port': _port,
      'roomCode': room.roomCode,
    });

    return '$_localIp:$_port';
  }

  void _handleConnection(WebSocketChannel socket) {
    _lastPing[socket] = DateTime.now();
    socket.stream.listen(
      (data) {
        _lastPing[socket] = DateTime.now();
        try {
          final msg = jsonDecode(data as String) as Map<String, dynamic>;
          _onMessage(socket, msg);
        } catch (_) {
          // Ignore malformed socket payloads and keep the client connected.
        }
      },
      onDone: () => _onDisconnect(socket),
      onError: (_) => _onDisconnect(socket),
    );
  }

  void _onMessage(WebSocketChannel socket, Map<String, dynamic> msg) {
    final type = msg['type'] as String;
    switch (type) {
      case MessageType.joinRequest:
        _handleJoinRequest(socket, msg);
        break;
      case MessageType.reconnect:
        _handleReconnect(socket, msg);
        break;
      case MessageType.chatMessage:
        _handleChatMessage(socket, msg);
        break;
      case MessageType.dmMessage:
        _handleDmMessage(socket, msg);
        break;
      case MessageType.privateChatRequest:
        _handlePrivateChatRequest(socket, msg);
        break;
      case MessageType.privateChatRequestAccept:
        _handlePrivateChatRequestAccept(socket, msg);
        break;
      case MessageType.privateChatRequestDecline:
        _handlePrivateChatRequestDecline(socket, msg);
        break;
      case MessageType.joinChatRequest:
        _handleJoinChatRequest(socket, msg);
        break;
      case MessageType.joinChatAccept:
        _handleJoinChatAccept(socket, msg);
        break;
      case MessageType.joinChatDecline:
        _handleJoinChatDecline(socket, msg);
        break;
      case MessageType.privateMessage:
        _handlePrivateMessage(socket, msg);
        break;
      case MessageType.leavePrivateChat:
        _handleLeavePrivateChat(socket, msg);
        break;
      case MessageType.neighborDmMessage:
        _handleNeighborDmMessage(socket, msg);
        break;
      case MessageType.heartbeat:
        break;
      default:
        socket.sink.add(jsonEncode({
          'type': 'error',
          'message': 'Unknown message type: $type',
        }));
    }
  }

  void _handleJoinRequest(WebSocketChannel socket, Map<String, dynamic> msg) {
    final name = (msg['name'] as String? ?? '').trim();
    if (name.isEmpty || _socketToPlayer.containsKey(socket)) return;
    final normalizedName = name.toLowerCase();
    final duplicateName = room.players.values
            .any((p) => p.name.toLowerCase() == normalizedName) ||
        room.pendingRequests.values
            .any((p) => p.name.toLowerCase() == normalizedName);
    if (duplicateName) {
      socket.sink.add(jsonEncode({
        'type': 'error',
        'message': 'That name is already connected or awaiting approval.',
      }));
      return;
    }
    final playerId = _uuid.v4();
    final newPlayer = Player(id: playerId, name: name);
    room.pendingRequests[playerId] = newPlayer;
    _socketToPlayer[socket] = playerId;
    _clients[playerId] = socket;
    socket.sink.add(jsonEncode({'type': 'join_pending', 'playerId': playerId}));
    _eventController
        .add({'type': 'new_join_request', 'playerId': playerId, 'name': name});
  }

  void approveJoin(String playerId, [int? seat]) {
    final player = room.pendingRequests.remove(playerId);
    if (player == null) return;

    final assignedSeat = seat ?? room.players.length;
    player.seat = assignedSeat;
    player.status = PlayerStatus.connected;
    room.players[playerId] = player;

    if (assignedSeat < room.seating.length) {
      room.seating.insert(assignedSeat, playerId);
    } else {
      room.seating.add(playerId);
    }
    _reindexSeats();

    final socket = _clients[playerId];
    socket?.sink.add(jsonEncode({
      'type': MessageType.joinApproved,
      'playerId': playerId,
      'seat': assignedSeat,
      'neighbors': room.getNeighbors(playerId),
      'seating': room.seating,
    }));
    if (room.scriptCharacters.isNotEmpty) {
      socket?.sink.add(jsonEncode({
        'type': MessageType.scriptCharactersUpdate,
        'characters': _serializeCharactersForWire(),
      }));
    }
    if (room.activeFabled.isNotEmpty) {
      socket?.sink.add(jsonEncode(_fabledMessage()));
    }
    if (room.isNight) {
      socket?.sink.add(jsonEncode({
        'type': MessageType.nightModeChange,
        'isNight': true,
        'dayNumber': room.dayNumber,
      }));
    }
    _sendPlayerBluffs(playerId);
    if (_countdownEndsAt != null &&
        _countdownEndsAt!.isAfter(DateTime.now().toUtc())) {
      socket?.sink.add(jsonEncode(_countdownMessage()));
    }
    broadcastToAll({
      'type': MessageType.seatingUpdate,
      'seating': room.seating,
      'players': room.players.map((k, v) => MapEntry(k, v.toJson())),
    });
  }

  void declineJoin(String playerId) {
    final player = room.pendingRequests.remove(playerId);
    if (player == null) return;

    final socket = _clients.remove(playerId);
    if (socket != null) {
      _socketToPlayer.remove(socket);
      _lastPing.remove(socket);
      socket.sink.add(jsonEncode({
        'type': MessageType.joinDeclined,
        'reason': 'The Storyteller declined your request to join.',
      }));
      socket.sink.close();
    }
    _eventController
        .add({'type': 'join_request_declined', 'playerId': playerId});
  }

  void kickPlayer(String playerId) {
    final player = room.players.remove(playerId);
    _clearPendingOutgoingRequests(playerId);
    if (player == null) return;

    final compactedSeating = <String>[];
    for (final seatedId in room.seating) {
      if (seatedId != playerId) {
        compactedSeating.add(seatedId);
      }
    }
    room.seating = compactedSeating;
    _reindexSeats();

    final socket = _clients.remove(playerId);
    if (socket != null) {
      _socketToPlayer.remove(socket);
      _lastPing.remove(socket);
      socket.sink.add(jsonEncode({
        'type': 'kicked',
        'reason': 'You were removed by the host',
      }));
      socket.sink.close();
    }

    // Handle private chats where the kicked player participated.
    final affectedChats = <String>[];
    room.privateChats.forEach((id, chat) {
      if (chat.participants.contains(playerId)) {
        chat.removeParticipant(playerId);
        if (chat.participants.isEmpty) {
          affectedChats.add(id);
        } else {
          final updated = List<String>.from(chat.participants);
          // Notify remaining participants that someone left.
          for (final pid in updated) {
            _clients[pid]?.sink.add(jsonEncode({
                  'type': 'participant_left',
                  'chatId': id,
                  'participants': updated,
                  'leftPlayerId': playerId,
                  'leftPlayerName': player.name,
                }));
          }
          // Broadcast the updated membership to everyone.
          broadcastToAll({
            'type': 'private_chat_membership_update',
            'chatId': id,
            'participants': updated,
          });
        }
      }
    });
    for (final id in affectedChats) {
      room.privateChats.remove(id);
      broadcastToAll({'type': 'private_chat_ended', 'chatId': id});
    }

    room.assignedCharacters.remove(playerId);
    room.extraCharacterData.remove(playerId);
    room.playerAlignments.remove(playerId);
    room.playerBluffs.remove(playerId);

    broadcastToAll({
      'type': MessageType.seatingUpdate,
      'seating': room.seating,
      'players': room.players.map((k, v) => MapEntry(k, v.toJson())),
    });
    _eventController.add({'type': 'player_kicked', 'playerId': playerId});
  }

  void swapPlayerSeats(String playerIdA, String playerIdB) {
    if (playerIdA == playerIdB) return;

    final indexA = room.seating.indexOf(playerIdA);
    final indexB = room.seating.indexOf(playerIdB);
    if (indexA == -1 || indexB == -1) return;

    final temp = room.seating[indexA];
    room.seating[indexA] = room.seating[indexB];
    room.seating[indexB] = temp;
    _reindexSeats();

    broadcastToAll({
      'type': MessageType.seatingUpdate,
      'seating': room.seating,
      'players': room.players.map((k, v) => MapEntry(k, v.toJson())),
    });
  }

  void _reindexSeats() {
    for (int i = 0; i < room.seating.length; i++) {
      final pid = room.seating[i];
      if (room.players.containsKey(pid)) {
        room.players[pid]!.seat = i;
      }
    }
  }

  void _handleReconnect(WebSocketChannel socket, Map<String, dynamic> msg) {
    final playerId = msg['playerId'] as String;
    final player = room.players[playerId];
    if (player != null && player.status == PlayerStatus.disconnected) {
      player.status = PlayerStatus.connected;
      _socketToPlayer[socket] = playerId;
      _clients[playerId] = socket;
      _lastPing[socket] = DateTime.now();
      socket.sink
          .add(jsonEncode({'type': 'reconnect_success', 'playerId': playerId}));

      final activeChats = <String, List<String>>{};
      for (final entry in room.privateChats.entries) {
        if (entry.value.containsPlayer(playerId)) {
          activeChats[entry.key] = entry.value.participants;
        }
      }
      if (activeChats.isNotEmpty) {
        socket.sink.add(jsonEncode({
          'type': 'private_chats_sync',
          'chats': activeChats,
        }));
      }

      // NEW: replay any neighbor-DM history this player is part of, so
      // reconnecting doesn't lose those threads the way it wouldn't lose
      // the Storyteller DM either.
      final neighborThreads = <String, List<Map<String, dynamic>>>{};
      room.neighborDmThreads.forEach((key, messages) {
        final parts = key.split('|');
        if (!parts.contains(playerId)) return;
        final peerId = parts[0] == playerId ? parts[1] : parts[0];
        neighborThreads[peerId] = messages.map((m) => m.toJson()).toList();
      });
      if (neighborThreads.isNotEmpty) {
        socket.sink.add(jsonEncode({
          'type': 'neighbor_dm_sync',
          'threads': neighborThreads,
        }));
      }

      if (room.scriptCharacters.isNotEmpty) {
        socket.sink.add(jsonEncode({
          'type': MessageType.scriptCharactersUpdate,
          'characters': _serializeCharactersForWire(),
        }));
      }
      if (room.activeFabled.isNotEmpty) {
        socket.sink.add(jsonEncode(_fabledMessage()));
      }
      final myCharacterId = room.assignedCharacters[playerId];
      if (myCharacterId != null && myCharacterId.isNotEmpty) {
        final extra = room.extraCharacterData[playerId];
        socket.sink.add(jsonEncode({
          'type': MessageType.characterAssigned,
          'characterId': myCharacterId,
          'alignment': room.playerAlignments[playerId] ?? 'good',
          if (extra != null) 'characterData': extra.toJson(),
        }));
      }
      if (room.isNight) {
        socket.sink.add(jsonEncode({
          'type': MessageType.nightModeChange,
          'isNight': true,
        }));
      }
      if (room.revealOrder.isNotEmpty) {
        socket.sink.add(jsonEncode({
          'type': MessageType.gameReveal,
          'order': room.revealOrder,
        }));
        for (final pid in room.revealedCardIds) {
          final p = room.players[pid];
          if (p == null) continue;
          socket.sink.add(jsonEncode({
            'type': MessageType.revealCardOpened,
            'playerId': pid,
            'playerName': p.name,
            'characterId': room.revealedCharacterIds[pid] ?? '',
            'alignment': room.revealedAlignments[pid] ?? 'good',
          }));
        }
      }

      broadcastToAll({
        'type': MessageType.seatingUpdate,
        'seating': room.seating,
        'players': room.players.map((k, v) => MapEntry(k, v.toJson())),
      });
    } else {
      socket.sink.add(jsonEncode({'type': 'reconnect_failed'}));
    }
  }

  void _handleChatMessage(WebSocketChannel socket, Map<String, dynamic> msg) {
    final playerId = _socketToPlayer[socket];
    final player = room.players[playerId];
    if (player == null) return;
    final perm = Permissions.canSend(
        room: room, sender: player, channel: 'main', isAdmin: false);
    if (!perm.allowed) {
      socket.sink.add(jsonEncode({'type': 'error', 'message': perm.reason}));
      return;
    }
    final chatMsg = ChatMessage(
      senderId: playerId!,
      senderName: player.name,
      text: msg['text'],
      replyToId: msg['replyToId'] as String?,
      replyToSenderName: msg['replyToSenderName'] as String?,
      replyToText: msg['replyToText'] as String?,
      voiceBase64: msg['voiceBase64'] as String?,
      voiceDurationMs: (msg['voiceDurationMs'] as num?)?.toInt(),
      voiceMime: msg['voiceMime'] as String?,
    );
    broadcastToAll({
      'type': MessageType.chatMessage,
      'message': chatMsg.toJson(),
    });
    _eventController.add({
      'type': MessageType.chatMessage,
      'message': chatMsg.toJson(),
    });
  }

  void adminSendMain(String text, {ChatMessage? replyTo}) {
    final chatMsg = ChatMessage(
        senderId: 'admin',
        senderName: 'Storyteller',
        text: text,
        replyToId: replyTo?.id,
        replyToSenderName: replyTo?.senderName,
        replyToText: replyTo?.text);
    broadcastToAll(
        {'type': MessageType.chatMessage, 'message': chatMsg.toJson()});
    _eventController
        .add({'type': MessageType.chatMessage, 'message': chatMsg.toJson()});
  }

  void adminSendMainVoice(String base64Audio,
      {int? durationMs, ChatMessage? replyTo, String? voiceMime}) {
    final chatMsg = ChatMessage(
      senderId: 'admin',
      senderName: 'Storyteller',
      text: '[Voice message]',
      voiceBase64: base64Audio,
      voiceDurationMs: durationMs,
      voiceMime: voiceMime,
      replyToId: replyTo?.id,
      replyToSenderName: replyTo?.senderName,
      replyToText: replyTo?.text,
    );
    broadcastToAll({
      'type': MessageType.chatMessage,
      'message': chatMsg.toJson(),
    });
    _eventController.add({
      'type': MessageType.chatMessage,
      'message': chatMsg.toJson(),
    });
  }

  void adminSendBluffs(List<String> characterIds, String targetPlayerId) {
    if (!room.players.containsKey(targetPlayerId) || characterIds.isEmpty) {
      return;
    }
    room.playerBluffs
        .putIfAbsent(targetPlayerId, () => [])
        .add(List<String>.from(characterIds));
    _sendPlayerBluffs(targetPlayerId);
    _eventController.add({
      'type': MessageType.bluffMessage,
      'bluffs': characterIds,
      'targetPlayerId': targetPlayerId,
      'targetName': room.players[targetPlayerId]?.name ?? targetPlayerId,
    });
  }

  void _sendPlayerBluffs(String playerId) {
    final socket = _clients[playerId];
    if (socket == null) return;
    socket.sink.add(jsonEncode({
      'type': MessageType.bluffMessage,
      'bluffs': room.playerBluffs[playerId] ?? const <List<String>>[],
    }));
  }

  // NEW: lets the storyteller delete one previously-sent bluff set (e.g.
  // to correct a mistaken claim), identified by its index in that
  // player's bluff history. Re-sends that player's full (now shorter)
  // bluff list so their device drops it too — the same "send the whole
  // current list" approach _sendPlayerBluffs already uses for additions.
  void removeBluffSet(String playerId, int index) {
    final list = room.playerBluffs[playerId];
    if (list == null || index < 0 || index >= list.length) return;
    list.removeAt(index);
    _sendPlayerBluffs(playerId);
  }

  void _handleDmMessage(WebSocketChannel socket, Map<String, dynamic> msg) {
    final playerId = _socketToPlayer[socket];
    final player = room.players[playerId];
    if (player == null) return;
    final chatMsg = ChatMessage(
      senderId: playerId!,
      senderName: player.name,
      text: msg['text'],
      replyToId: msg['replyToId'] as String?,
      replyToSenderName: msg['replyToSenderName'] as String?,
      replyToText: msg['replyToText'] as String?,
      voiceBase64: msg['voiceBase64'] as String?,
      voiceDurationMs: (msg['voiceDurationMs'] as num?)?.toInt(),
      voiceMime: msg['voiceMime'] as String?,
    );
    player.dmThread.add(chatMsg);
    _eventController.add({
      'type': 'dm_message',
      'playerId': playerId,
      'message': chatMsg.toJson()
    });
    socket.sink.add(jsonEncode({
      'type': MessageType.dmMessage,
      'message': chatMsg.toJson(),
      'fromAdmin': false,
    }));
  }

  void adminSendDm(String playerId, String text,
      {ChatMessage? replyTo,
      String? voiceBase64,
      int? durationMs,
      String? voiceMime}) {
    final player = room.players[playerId];
    if (player == null) return;
    final chatMsg = ChatMessage(
      senderId: 'admin',
      senderName: 'Storyteller',
      text: text,
      replyToId: replyTo?.id,
      replyToSenderName: replyTo?.senderName,
      replyToText: replyTo?.text,
      voiceBase64: voiceBase64,
      voiceDurationMs: durationMs,
      voiceMime: voiceMime,
    );
    player.dmThread.add(chatMsg);
    _clients[playerId]?.sink.add(jsonEncode({
          'type': MessageType.dmMessage,
          'message': chatMsg.toJson(),
          'fromAdmin': true,
        }));
    _eventController.add({
      'type': 'dm_message',
      'playerId': playerId,
      'message': chatMsg.toJson()
    });
  }

  bool _isPlayerInAnyPrivateChat(String playerId) {
    return room.privateChats.values
        .any((chat) => chat.participants.contains(playerId));
  }

  void _handlePrivateChatRequest(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final initiatorId = _socketToPlayer[socket];
    final targetId = msg['targetId'] as String;
    final initiator = room.players[initiatorId];
    final target = room.players[targetId];
    if (initiator == null || target == null) return;

    final perm = Permissions.canSend(
        room: room,
        sender: initiator,
        channel: 'private_request',
        isAdmin: false,
        targetPlayerId: targetId);
    if (!perm.allowed) {
      socket.sink.add(jsonEncode(
          {'type': 'error', 'message': perm.reason, 'targetId': targetId}));
      return;
    }

    if (_isPlayerInAnyPrivateChat(initiatorId!)) {
      socket.sink.add(jsonEncode({
        'type': 'error',
        'message':
            "You're already in a private chat. Leave it before starting another.",
        'targetId': targetId,
      }));
      return;
    }
    if (_isPlayerInAnyPrivateChat(targetId)) {
      socket.sink.add(jsonEncode({
        'type': 'error',
        'message':
            '${target.name} is already in a private chat. You can request to join that chat instead.',
        'targetId': targetId,
      }));
      return;
    }

    // NEW: track this outgoing request so it can be proactively
    // cancelled if the requester's OTHER pending request resolves
    // first — see _handlePrivateChatRequestAccept.
    _pendingOutgoingRequests.putIfAbsent(initiatorId, () => {}).add(targetId);

    _clients[targetId]?.sink.add(jsonEncode({
          'type': 'private_chat_request_received',
          'requesterId': initiatorId,
          'requesterName': initiator.name,
        }));
  }

  void _handlePrivateChatRequestAccept(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final accepterId = _socketToPlayer[socket];
    final requesterId = msg['requesterId'] as String;
    if (accepterId == null) return;
    final accepter = room.players[accepterId];
    final requester = room.players[requesterId];
    if (accepter == null || requester == null) return;
    if (_isPlayerInAnyPrivateChat(accepterId) ||
        _isPlayerInAnyPrivateChat(requesterId)) {
      final busySide = _isPlayerInAnyPrivateChat(accepterId)
          ? "you're"
          : '${requester.name} is';
      socket.sink.add(jsonEncode({
        'type': 'error',
        'message':
            'That request is no longer available — $busySide already in a private chat.',
      }));
      _clients[requesterId]?.sink.add(jsonEncode({
            'type': 'private_chat_request_declined',
            'targetId': accepterId,
          }));
      _pendingOutgoingRequests[requesterId]?.remove(accepterId);
      return;
    }

    final chatId = _uuid.v4();
    final chat =
        PrivateChat(sessionId: chatId, participants: [requesterId, accepterId]);
    room.privateChats[chatId] = chat;

    for (final pid in chat.participants) {
      _clients[pid]?.sink.add(jsonEncode({
            'type': 'private_chat_created',
            'chatId': chatId,
            'participants': chat.participants,
          }));
    }

    // ADDED: broadcast membership update to everyone.
    broadcastToAll({
      'type': 'private_chat_membership_update',
      'chatId': chatId,
      'participants': chat.participants,
    });

    // NEW: cancel this requester's OTHER outstanding requests to
    // different players immediately, so those players' incoming
    // banners disappear right away instead of waiting for the 20s
    // auto-decline timeout.
    final otherTargets = _pendingOutgoingRequests.remove(requesterId) ?? {};
    otherTargets.remove(accepterId);
    for (final otherTargetId in otherTargets) {
      _clients[otherTargetId]?.sink.add(jsonEncode({
            'type': 'private_chat_request_cancelled',
            'requesterId': requesterId,
          }));
    }

    _eventController.add({
      'type': 'private_chat_created',
      'chatId': chatId,
      'participants': chat.participants,
    });
  }

  void _handlePrivateChatRequestDecline(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final requesterId = msg['requesterId'] as String;
    final declinerId = _socketToPlayer[socket];
    if (declinerId != null) {
      _pendingOutgoingRequests[requesterId]?.remove(declinerId);
    }
    _clients[requesterId]?.sink.add(jsonEncode({
          'type': 'private_chat_request_declined',
          'targetId': declinerId,
        }));
  }

  void _clearPendingOutgoingRequests(String playerId) {
    _pendingOutgoingRequests.remove(playerId);
    for (final set in _pendingOutgoingRequests.values) {
      set.remove(playerId);
    }
  }

  void _handleJoinChatRequest(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final requesterId = _socketToPlayer[socket];
    final chatId = msg['chatId'] as String;
    final chat = room.privateChats[chatId];
    if (chat == null || requesterId == null) return;
    final player = room.players[requesterId];
    if (player == null) return;
    if (chat.participants.contains(requesterId)) return;
    if (_isPlayerInAnyPrivateChat(requesterId)) {
      socket.sink.add(jsonEncode({
        'type': 'error',
        'message':
            "You're already in a private chat. Leave it before joining another.",
      }));
      return;
    }
    final perm = Permissions.canSend(
        room: room,
        sender: player,
        channel: 'private:$chatId',
        isAdmin: false,
        targetPrivateChatId: chatId);
    if (!perm.allowed) {
      socket.sink.add(jsonEncode({'type': 'error', 'message': perm.reason}));
      return;
    }
    for (final pid in chat.participants) {
      _clients[pid]?.sink.add(jsonEncode({
            'type': 'join_chat_request_received',
            'chatId': chatId,
            'requesterId': requesterId,
            'requesterName': player.name,
          }));
    }
  }

  void _handleJoinChatAccept(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final acceptorId = _socketToPlayer[socket];
    final chatId = msg['chatId'] as String;
    final requesterId = msg['requesterId'] as String;
    final chat = room.privateChats[chatId];
    if (chat == null ||
        acceptorId == null ||
        !chat.participants.contains(acceptorId) ||
        _isPlayerInAnyPrivateChat(requesterId)) return;
    chat.addParticipant(requesterId);
    final updated = List<String>.from(chat.participants);
    for (final pid in updated) {
      _clients[pid]?.sink.add(jsonEncode({
            'type': 'participant_joined',
            'chatId': chatId,
            'participants': updated,
            'newParticipantId': requesterId,
          }));
    }

    // ADDED: broadcast membership update to everyone.
    broadcastToAll({
      'type': 'private_chat_membership_update',
      'chatId': chatId,
      'participants': updated,
    });

    _eventController.add({
      'type': 'private_chat_updated',
      'chatId': chatId,
      'participants': updated,
    });
  }

  void _handleJoinChatDecline(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final requesterId = msg['requesterId'];
    final chatId = msg['chatId'];
    _clients[requesterId]?.sink.add(jsonEncode({
          'type': 'join_chat_declined',
          'chatId': chatId,
        }));
  }

  void _handlePrivateMessage(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final senderId = _socketToPlayer[socket];
    final chatId = msg['chatId'] as String;
    final chat = room.privateChats[chatId];
    if (chat == null ||
        senderId == null ||
        !chat.participants.contains(senderId)) return;
    final player = room.players[senderId];
    if (player == null) return;
    final perm = Permissions.canSend(
        room: room,
        sender: player,
        channel: 'private:$chatId',
        isAdmin: false,
        targetPrivateChatId: chatId);
    if (!perm.allowed) {
      socket.sink.add(jsonEncode({'type': 'error', 'message': perm.reason}));
      return;
    }
    final chatMsg = ChatMessage(
      senderId: senderId,
      senderName: player.name,
      text: msg['text'],
      channelId: chatId,
      replyToId: msg['replyToId'] as String?,
      replyToSenderName: msg['replyToSenderName'] as String?,
      replyToText: msg['replyToText'] as String?,
      voiceBase64: msg['voiceBase64'] as String?,
      voiceDurationMs: (msg['voiceDurationMs'] as num?)?.toInt(),
      voiceMime: msg['voiceMime'] as String?,
    );
    chat.messages.add(chatMsg);
    for (final pid in chat.participants) {
      _clients[pid]?.sink.add(jsonEncode({
            'type': MessageType.privateMessage,
            'chatId': chatId,
            'message': chatMsg.toJson(),
          }));
    }
    _eventController.add({
      'type': 'private_message',
      'chatId': chatId,
      'message': chatMsg.toJson(),
    });
  }

  void _handleLeavePrivateChat(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    final playerId = _socketToPlayer[socket];
    final chatId = msg['chatId'] as String;
    final chat = room.privateChats[chatId];
    if (chat == null || playerId == null) return;
    final leftPlayerName = room.players[playerId]?.name;
    chat.removeParticipant(playerId);
    if (chat.participants.isEmpty) {
      room.privateChats.remove(chatId);
      broadcastToAll({'type': 'private_chat_ended', 'chatId': chatId});
    } else {
      final updated = List<String>.from(chat.participants);
      for (final pid in updated) {
        _clients[pid]?.sink.add(jsonEncode({
              'type': 'participant_left',
              'chatId': chatId,
              'participants': updated,
              'leftPlayerId': playerId,
              'leftPlayerName': leftPlayerName,
            }));
      }

      // ADDED: broadcast membership update to everyone.
      broadcastToAll({
        'type': 'private_chat_membership_update',
        'chatId': chatId,
        'participants': updated,
      });

      _eventController.add({
        'type': 'private_chat_updated',
        'chatId': chatId,
        'participants': updated,
      });
    }
  }

  void _handleNeighborDmMessage(
      WebSocketChannel socket, Map<String, dynamic> msg) {
    // NEW: direct player-to-player message with a current seating
    // neighbor. Deliberately mirrors _handleDmMessage/adminSendDm below —
    // no Permissions.canSend call, so it's unaffected by chat lock or
    // mute, exactly like the Storyteller DM. The ONLY gate is the
    // neighbor check itself, which is the entire point of the feature: no
    // accept/decline, no exclusivity check against privateChats — this can
    // run at the same time as an active private chat.
    final senderId = _socketToPlayer[socket];
    final targetId = msg['targetId'] as String?;
    if (senderId == null || targetId == null) return;
    final sender = room.players[senderId];
    final target = room.players[targetId];
    if (sender == null || target == null) return;

    if (!room.areNeighbors(senderId, targetId)) {
      socket.sink.add(jsonEncode({
        'type': 'error',
        'message': 'You can only message your current neighbors this way.',
      }));
      return;
    }

    final chatMsg = ChatMessage(
      senderId: senderId,
      senderName: sender.name,
      text: msg['text'],
      replyToId: msg['replyToId'] as String?,
      replyToSenderName: msg['replyToSenderName'] as String?,
      replyToText: msg['replyToText'] as String?,
      voiceBase64: msg['voiceBase64'] as String?,
      voiceDurationMs: (msg['voiceDurationMs'] as num?)?.toInt(),
      voiceMime: msg['voiceMime'] as String?,
    );
    final key = RoomState.neighborDmKey(senderId, targetId);
    room.neighborDmThreads.putIfAbsent(key, () => []).add(chatMsg);

    for (final participantId in [senderId, targetId]) {
      final peerId = participantId == senderId ? targetId : senderId;
      _clients[participantId]?.sink.add(jsonEncode({
            'type': MessageType.neighborDmMessage,
            'peerId': peerId,
            'message': chatMsg.toJson(),
          }));
    }

    // NEW: lets the storyteller's own screen follow every neighbor DM as
    // it happens, the same way _handleChatMessage/_handleDmMessage
    // already notify the host device of everything else. The message
    // itself is already sitting in room.neighborDmThreads (mutated
    // above) — this event just tells GameProvider's own UI to rebuild
    // and (if the storyteller isn't currently watching this exact
    // thread) flag it unread. Deliberately player-agnostic: this fires
    // identically whether the sender is the native app or the browser
    // client, since both speak the same neighbor_dm_message type.
    _eventController.add({
      'type': 'neighbor_dm_message',
      'key': key,
    });
  }

  void setChatMode(ChatMode mode) {
    room.chatMode = mode;
    broadcastToAll({'type': MessageType.chatModeChange, 'mode': mode.name});
    if (mode == ChatMode.locked) _enforceChatModeLock();
  }

  void _enforceChatModeLock() {
    room.privateChats.clear();
    broadcastToAll({'type': 'all_private_chats_ended'});
  }

  void setNeighborRestriction(bool on) {
    room.neighborRestriction = on;
    broadcastToAll({'type': MessageType.neighborModeChange, 'on': on});
    if (on) _enforceNeighborRestriction();
  }

  void setNight(bool night) {
    if (room.isNight == night) return;
    if (!night) room.dayNumber++;
    room.isNight = night;
    // NEW: falling night closes every active private chat, the same way
    // locking chat already does (_enforceChatModeLock). Only fires on
    // the transition INTO night — waking at dawn doesn't need to close
    // anything, since nothing new could open overnight anyway.
    if (night) _enforceNightChatClosure();

    broadcastToAll({
      'type': MessageType.nightModeChange,
      'isNight': night,
      'dayNumber': room.dayNumber,
    });
    _eventController.add({
      'type': MessageType.nightModeChange,
      'isNight': night,
      'dayNumber': room.dayNumber
    });
  }

  void _enforceNightChatClosure() {
    if (room.privateChats.isEmpty) return;
    room.privateChats.clear();
    broadcastToAll({'type': 'all_private_chats_ended'});
  }

  void _enforceNeighborRestriction() {
    // NEW: neighbor restriction now forbids private chats entirely —
    // not just chats between non-neighbors — so every active private
    // chat closes the instant it's turned on.
    if (room.privateChats.isEmpty) return;
    room.privateChats.clear();
    broadcastToAll({'type': 'all_private_chats_ended'});
  }

  void mutePlayer(String playerId, bool mute) {
    final player = room.players[playerId];
    if (player == null) return;
    player.muted = mute;
    broadcastToAll({
      'type': mute ? MessageType.mutePlayer : MessageType.unmutePlayer,
      'playerId': playerId,
      'muted': mute,
    });
  }

  void setPlayerAlive(String playerId, bool alive) {
    final player = room.players[playerId];
    if (player == null) return;
    player.alive = alive;
    player.ghostVoteUsed = false;
    broadcastToAll({
      'type': MessageType.setPlayerAlive,
      'playerId': playerId,
      'alive': alive,
      'ghostVoteUsed': false,
    });
  }

  void setGhostVoteUsed(String playerId, bool used) {
    final player = room.players[playerId];
    if (player == null) return;
    player.ghostVoteUsed = used;
    broadcastToAll({
      'type': MessageType.setGhostVoteUsed,
      'playerId': playerId,
      'ghostVoteUsed': used,
    });
  }

  void setAdminNote(String playerId, PlayerNote note) {
    final player = room.players[playerId];
    if (player == null) return;
    player.adminNotes = note;
    // Notify listeners (host UI) that an admin note changed for this player.
    _eventController.add({
      'type': 'admin_note_updated',
      'playerId': playerId,
      'note': note.toJson(),
    });
  }

  void forceCloseChat(String chatId) {
    room.privateChats.remove(chatId);
    broadcastToAll({'type': 'private_chat_ended', 'chatId': chatId});
  }

  void forceCloseAllChats() {
    room.privateChats.clear();
    broadcastToAll({'type': 'all_private_chats_ended'});
  }

  void addScriptImage(String filePath) {
    final fileName = path.basename(filePath);
    final destDir = Directory('${Directory.systemTemp.path}/botc_scripts');
    if (!destDir.existsSync()) destDir.createSync(recursive: true);
    final destFile = File('${destDir.path}/$fileName');
    File(filePath).copySync(destFile.path);
    room.scriptImagePaths.add(fileName);
    broadcastToAll({
      'type': 'script_images_updated',
      'urls': room.scriptImagePaths
          .map((f) => 'http://$_localIp:$_port/script/$f')
          .toList(),
    });
  }

  void removeScriptImage(String fileName) {
    if (!room.scriptImagePaths.contains(fileName)) return;
    room.scriptImagePaths.remove(fileName);
    final destDir = Directory('${Directory.systemTemp.path}/botc_scripts');
    final file = File('${destDir.path}/$fileName');
    if (file.existsSync()) {
      file.deleteSync();
    }
    broadcastToAll({
      'type': 'script_images_updated',
      'urls': room.scriptImagePaths
          .map((f) => 'http://$_localIp:$_port/script/$f')
          .toList(),
    });
  }

  // NEW: serializes characters for the wire with an added 'iconUrl'
  // field — the Flutter app resolves icons locally from its own
  // bundled assets, but the browser client can't reach those, so the
  // host serves them over HTTP via the '/icons/<file>' route below.
  List<Map<String, dynamic>> _serializeCharactersForWire([
    List<ScriptCharacter>? characters,
  ]) {
    final source = characters ?? room.scriptCharacters;
    return source.map((c) {
      final json = c.toJson();
      final fileName = CharacterIcons.instance.fileNameFor(c);
      if (fileName != null) {
        json['iconUrl'] = 'http://$_localIp:$_port/icons/$fileName';
      }
      return json;
    }).toList();
  }

  Map<String, dynamic> _fabledMessage() => {
        'type': MessageType.fabledUpdate,
        'characters': _serializeCharactersForWire(room.activeFabled),
      };

  void setActiveFabled(List<ScriptCharacter> chars) {
    room.activeFabled = List<ScriptCharacter>.from(chars);
    broadcastToAll(_fabledMessage());
  }

  Future<Response> _serveIconAsset(String fileName) async {
    if (fileName.isEmpty) return Response.notFound('Not found');
    try {
      final data = await rootBundle.load('assets/icons/$fileName');
      final bytes = data.buffer.asUint8List();
      final lower = fileName.toLowerCase();
      final contentType = lower.endsWith('.png')
          ? 'image/png'
          : (lower.endsWith('.jpg') || lower.endsWith('.jpeg'))
              ? 'image/jpeg'
              : 'application/octet-stream';
      return Response.ok(bytes, headers: {'content-type': contentType});
    } catch (_) {
      return Response.notFound('Not found');
    }
  }

  void setScriptCharacters(List<ScriptCharacter> characters) {
    room.scriptCharacters = characters;
    broadcastToAll({
      'type': MessageType.scriptCharactersUpdate,
      'characters': _serializeCharactersForWire(),
    });
  }

  ScriptCharacter? _findCharacter(String id) {
    for (final c in room.scriptCharacters) {
      if (c.id == id) return c;
    }
    return null;
  }

  void assignCharacters(Map<String, String> assignments) {
    assignments.forEach((playerId, characterId) {
      if (!room.players.containsKey(playerId)) return;
      room.assignedCharacters[playerId] = characterId;

      // NEW: seed a default alignment from the character's team so a
      // freshly-assigned Imp shows evil/red immediately without an
      // extra step — the Storyteller can still flip it after.
      if (characterId.isNotEmpty) {
        final character = _findCharacter(characterId);
        final isEvilTeam = character != null &&
            (character.team == 'minion' || character.team == 'demon');
        room.playerAlignments[playerId] = isEvilTeam ? 'evil' : 'good';
      }

      final socket = _clients[playerId];
      if (socket != null) {
        socket.sink.add(jsonEncode({
          'type': MessageType.characterAssigned,
          'characterId': characterId,
          'alignment': room.playerAlignments[playerId] ?? 'good',
        }));
      }
    });
    _eventController.add({'type': 'characters_assigned'});
  }

  // NEW: single-player assignment that can carry full character data
  // for anything outside the current script — an official character
  // picked via "show all characters", or a custom typed one. Persists
  // it in room.extraCharacterData so a reconnect or the end-game
  // reveal can still resend the ability/flavor text later.
  void assignCharacterWithData(
      String playerId, String characterId, ScriptCharacter? characterData,
      {String? alignment}) {
    if (!room.players.containsKey(playerId)) return;
    room.assignedCharacters[playerId] = characterId;

    final inScript =
        characterId.isNotEmpty && _findCharacter(characterId) != null;
    if (!inScript && characterData != null) {
      room.extraCharacterData[playerId] = characterData;
    } else {
      room.extraCharacterData.remove(playerId);
    }

    if (characterId.isNotEmpty) {
      final resolved = characterData ?? _findCharacter(characterId);
      final isEvilTeam = resolved != null &&
          (resolved.team == 'minion' || resolved.team == 'demon');
      room.playerAlignments[playerId] =
          alignment ?? (isEvilTeam ? 'evil' : 'good');
    }

    final socket = _clients[playerId];
    if (socket != null) {
      final extra = room.extraCharacterData[playerId];
      socket.sink.add(jsonEncode({
        'type': MessageType.characterAssigned,
        'characterId': characterId,
        'alignment': room.playerAlignments[playerId] ?? 'good',
        if (extra != null) 'characterData': extra.toJson(),
      }));
    }
    _eventController.add({'type': 'characters_assigned'});
  }

  // NEW: lets the Storyteller flip a player's alignment on its own,
  // with no character reassignment needed — e.g. turning a demon good,
  // or a townsfolk secretly evil, mid-game.
  void setPlayerAlignment(String playerId, String alignment) {
    if (!room.players.containsKey(playerId)) return;
    room.playerAlignments[playerId] = alignment;
    final socket = _clients[playerId];
    if (socket != null) {
      socket.sink.add(jsonEncode({
        'type': MessageType.setPlayerAlignment,
        'alignment': alignment,
      }));
    }
    _eventController
        .add({'type': 'player_alignment_changed', 'playerId': playerId});
  }

  // NEW: Storyteller's final call on who won, once every card is
  // (or is being) revealed. Broadcast once — the reveal screen on
  // every device turns this into a glossy popup rather than an
  // inline banner.
  void declareWinner(String winningAlignment) {
    broadcastToAll({
      'type': MessageType.gameWinner,
      'alignment': winningAlignment,
    });
  }

  // NEW: resets every per-round secret (characters, alignments,
  // bluffs, reveal progress) while keeping everyone connected and
  // seated — a fresh game without ending the session.
  void startNewGame() {
    room.assignedCharacters.clear();
    room.playerAlignments.clear();
    room.extraCharacterData.clear();
    room.playerBluffs.clear();
    room.privateChats.clear();
    room.neighborDmThreads.clear();
    room.isNight = false;
    room.dayNumber = 1;
    _pendingOutgoingRequests.clear();
    for (final player in room.players.values) {
      player.dmThread.clear();
      player.alive = true;
      player.ghostVoteUsed = false;
    }
    room.revealOrder = [];
    room.revealedCardIds = {};
    room.revealedCharacterIds = {};
    room.revealedAlignments = {};
    room.activeFabled = [];
    cancelCountdown();
    stopCountdownSound();
    broadcastToAll({
      'type': MessageType.nightModeChange,
      'isNight': false,
      'dayNumber': 1,
    });
    broadcastToAll({
      'type': MessageType.seatingUpdate,
      'seating': room.seating,
      'players':
          room.players.map((key, player) => MapEntry(key, player.toJson())),
    });
    broadcastToAll(_fabledMessage());
    broadcastToAll({'type': 'new_game_started'});
  }

  void revealCharacters() {
    final order = <String>[];
    for (final pid in room.seating) {
      if (room.players.containsKey(pid)) order.add(pid);
    }
    room.revealOrder = order;
    room.revealedCardIds = {};
    room.revealedCharacterIds = {};
    room.revealedAlignments = {};
    // Players get ONLY the ordered id list — no names, no character ids.
    // That's the entire security boundary: their device simply never
    // receives the answer until revealCard() below sends that one entry.
    broadcastToAll({
      'type': MessageType.gameReveal,
      'order': order,
    });

    // The host's own screen gets the full picture immediately, same as
    // before — the storyteller already knows every assignment (they made
    // them). What's being staged here is what the TABLE sees, not what
    // the storyteller sees.
    final assignments = <Map<String, dynamic>>[];
    for (final pid in order) {
      final p = room.players[pid]!;
      assignments.add({
        'playerId': pid,
        'playerName': p.name,
        'characterId': room.assignedCharacters[pid] ?? '',
      });
    }
    _eventController.add({
      'type': MessageType.gameReveal,
      'assignments': assignments,
    });
  }

  // NEW: storyteller taps one card on the reveal screen. Broadcasts that
  // single player's name + character to every device at once, so the
  // "flip" is a live, synced moment rather than something everyone reads
  // quietly on their own screen whenever they happen to scroll to it.
  // Re-tapping an already-open card is a no-op here — RevealScreen
  // switches its tap handler to "open the ability sheet" once a card is
  // already revealed, so this only fires for genuinely new reveals.
  void revealCard(String playerId) {
    if (!room.revealOrder.contains(playerId)) return;
    if (room.revealedCardIds.contains(playerId)) return;
    final player = room.players[playerId];
    if (player == null) return;
    final characterId = room.assignedCharacters[playerId] ?? '';
    final alignment = room.playerAlignments[playerId] ?? 'good';
    room.revealedCardIds.add(playerId);
    room.revealedCharacterIds[playerId] = characterId;
    room.revealedAlignments[playerId] = alignment;
    final revealExtra = room.extraCharacterData[playerId];
    broadcastToAll({
      'type': MessageType.revealCardOpened,
      'playerId': playerId,
      'playerName': player.name,
      'characterId': characterId,
      'alignment': alignment,
      if (revealExtra != null) 'characterData': revealExtra.toJson(),
    });
    _eventController.add({
      'type': MessageType.revealCardOpened,
      'playerId': playerId,
    });
  }

  // FIX: adminWatchChat used to live here and replay every message
  // already in `chat.messages` back through `_eventController`, which
  // GameProvider's `_onHostEvent` then appended onto that SAME list
  // object (host and its own UI share one RoomState) — duplicating the
  // whole history every time the storyteller opened Watch on a chat, and
  // re-duplicating the (now doubled) list every time they reopened it.
  // AdminPanel's Watch view already reads
  // `room.privateChats[chatId]?.messages` directly, so the history is
  // visible the instant Watch opens with no replay needed — the method
  // was removed rather than fixed in place, since it had nothing left to
  // do. See GameProvider.watchChat(), which no longer calls it.

  void startCountdown(int seconds) {
    _countdownEndsAt = DateTime.now().toUtc().add(Duration(seconds: seconds));
    final message = _countdownMessage();
    broadcastToAll(message);
    _eventController.add(message);
  }

  Map<String, dynamic> _countdownMessage() => {
        'type': MessageType.countdownStart,
        'endsAt': _countdownEndsAt!.toIso8601String(),
      };

  void cancelCountdown() {
    _countdownEndsAt = null;
    broadcastToAll({'type': MessageType.countdownCancel});
    _eventController.add({'type': MessageType.countdownCancel});
  }

  // NEW: lets the Storyteller silence the alarm on every device right
  // now, independent of cancelling the countdown itself.
  void stopCountdownSound() {
    broadcastToAll({'type': 'stop_countdown_alarm'});
  }

  void _onDisconnect(WebSocketChannel socket) {
    final playerId = _socketToPlayer.remove(socket);
    _lastPing.remove(socket);
    if (playerId != null) {
      _clearPendingOutgoingRequests(playerId);
      _clients.remove(playerId);
      final player = room.players.remove(playerId);
      final pendingPlayer = room.pendingRequests.remove(playerId);
      if (player != null || pendingPlayer != null) {
        room.seating.remove(playerId);
        _reindexSeats();
        room.assignedCharacters.remove(playerId);
        room.extraCharacterData.remove(playerId);
        room.playerAlignments.remove(playerId);
        room.playerBluffs.remove(playerId);
        broadcastToAll({
          'type': MessageType.seatingUpdate,
          'seating': room.seating,
          'players': room.players.map((k, v) => MapEntry(k, v.toJson())),
        });
        if (player != null) {
          _eventController.add({
            'type': 'player_disconnected_notice',
            'playerName': player.name,
          });
        }
        final affected = <String>[];
        room.privateChats.forEach((id, chat) {
          if (chat.participants.contains(playerId)) {
            chat.removeParticipant(playerId);
            if (chat.participants.isEmpty) {
              affected.add(id);
            } else {
              final updated = List<String>.from(chat.participants);
              // Notify remaining participants that someone left.
              for (final pid in updated) {
                _clients[pid]?.sink.add(jsonEncode({
                      'type': 'participant_left',
                      'chatId': id,
                      'participants': updated,
                      'leftPlayerId': playerId,
                      'leftPlayerName': player?.name,
                    }));
              }
              // Broadcast the updated membership to everyone.
              broadcastToAll({
                'type': 'private_chat_membership_update',
                'chatId': id,
                'participants': updated,
              });
            }
          }
        });
        for (final id in affected) {
          room.privateChats.remove(id);
          broadcastToAll({'type': 'private_chat_ended', 'chatId': id});
        }
        _eventController
            .add({'type': 'player_disconnected', 'playerId': playerId});
      }
    }
  }

  // NEW: storyteller broadcast — text shown as a hard-to-miss popup on
  // every targeted player's device. null/empty targetPlayerIds means
  // "everyone".
  void sendAnnouncement(String text, List<String>? targetPlayerIds) {
    final payload = jsonEncode({'type': 'announcement', 'text': text});
    if (targetPlayerIds == null || targetPlayerIds.isEmpty) {
      for (final socket in _clients.values) {
        socket.sink.add(payload);
      }
    } else {
      for (final pid in targetPlayerIds) {
        _clients[pid]?.sink.add(payload);
      }
    }
  }

  void broadcastToAll(Map<String, dynamic> msg) {
    final encoded = jsonEncode(msg);
    for (final socket in _clients.values) {
      socket.sink.add(encoded);
    }
  }

  void dispose() {
    for (final socket in _onlineSockets.values) {
      socket.closeFromRemote();
    }
    _onlineSockets.clear();
    _httpServer?.close();
    _pingChecker?.cancel();
    _eventController.close();
  }
}
