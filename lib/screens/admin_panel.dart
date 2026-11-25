import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/room_state.dart';
import '../models/player.dart';
import '../widgets/countdown_banner.dart';
import '../widgets/bluff_message_bubble.dart';
import 'reveal_screen.dart';
import '../widgets/glow_popup.dart';
import 'admin_players_tab.dart';
import 'admin_script_tab.dart';
import 'admin_game_tab.dart';
import 'dart:async';
import '../theme/app_theme.dart'; // NEW
import '../services/voice_recorder_service.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/swipe_reply.dart';

enum AdminMainTab { chat, players, script, game }

enum AdminView { main, dm, watch, neighborWatch }

class AdminPanel extends StatefulWidget {
  const AdminPanel({super.key});
  @override
  State<AdminPanel> createState() => _AdminPanelState();
}

class _AdminPanelState extends State<AdminPanel> {
  AdminMainTab _mainTab = AdminMainTab.chat;
  AdminView _view = AdminView.main;
  String? _activeId;
  String? _activeNeighborKey;
  final _mainController = TextEditingController();
  final _dmController = TextEditingController();
  final _mainReply = ValueNotifier<ChatMessage?>(null);
  final _dmReply = ValueNotifier<ChatMessage?>(null);
  final _recordingVoice = ValueNotifier<bool>(false);
  final _voiceRecorder = VoiceRecorderService();

  final _mainFocus = FocusNode();
  final _dmFocus = FocusNode();

  @override
  void dispose() {
    _mainFocus.dispose();
    _dmFocus.dispose();
    _mainReply.dispose();
    _dmReply.dispose();
    _recordingVoice.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  void _unfocusAll() {
    _mainFocus.unfocus();
    _dmFocus.unfocus();
  }

  void openDm(String playerId) {
    _unfocusAll();
    context.read<GameProvider>().openDm(playerId);
    setState(() {
      _mainTab = AdminMainTab.chat;
      _view = AdminView.dm;
      _activeId = playerId;
    });
  }

  void openWatch(String chatId) {
    _unfocusAll();
    context.read<GameProvider>().watchChat(chatId);
    setState(() {
      _mainTab = AdminMainTab.chat;
      _view = AdminView.watch;
      _activeId = chatId;
    });
  }

  void openNeighborWatch(String key) {
    _unfocusAll();
    context.read<GameProvider>().watchNeighborDm(key);
    setState(() {
      _mainTab = AdminMainTab.chat;
      _view = AdminView.neighborWatch;
      _activeNeighborKey = key;
    });
  }

  String neighborPairLabel(RoomState room, String key) {
    final parts = key.split('|');
    if (parts.length != 2) return 'Neighbor DM';
    final a = room.players[parts[0]]?.name ?? 'Unknown';
    final b = room.players[parts[1]]?.name ?? 'Unknown';
    return '$a ↔ $b';
  }

  void _backToChatMain() {
    _unfocusAll();
    if (_view == AdminView.watch) {
      context.read<GameProvider>().stopWatchingChat();
    }
    if (_view == AdminView.neighborWatch) {
      context.read<GameProvider>().stopWatchingNeighborDm();
    }
    if (_view == AdminView.dm) context.read<GameProvider>().closeDm();
    setState(() {
      _view = AdminView.main;
      _activeId = null;
      _activeNeighborKey = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final room = provider.room!;

    if (provider.revealActive && !provider.revealScreenOpen) {
      provider.markRevealScreenOpen();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const RevealScreen()),
        ).then((_) {
          // Fires no matter HOW the reveal screen closes — back
          // button, Leave Game, or the automatic pop that fires when
          // Start New Game is pressed — so the guard is always
          // correctly reset for the next reveal, however many games
          // are played in the same session.
          if (!context.mounted) return;
          context.read<GameProvider>().markRevealScreenClosed();
        });
      });
    }
    final queuedPopup = provider.consumeNextPopup();
    if (queuedPopup != null) {
      if (queuedPopup.type == GamePopupType.winner) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          showWinnerPopup(context, queuedPopup.alignment ?? 'good',
              onClosed: () {
            if (mounted) context.read<GameProvider>().popupClosed();
          });
        });
      } else {
        // Character/announcement popups never target the host device —
        // release the lock defensively so the queue can't get stuck.
        provider.popupClosed();
      }
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(provider, room),
      body: Stack(
        children: [
          _buildBody(provider, room),
          const CountdownFloatingCard(),
          _BannerStack(onOpenDm: openDm), // Replaces individual notice banners
        ],
      ),
      bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
          ? null
          : _buildBottomNav(provider, room),
    );
  }

  PreferredSizeWidget _buildAppBar(GameProvider provider, RoomState room) {
    String title = 'General Chat';
    if (_mainTab == AdminMainTab.players) title = 'Players';
    if (_mainTab == AdminMainTab.script) title = 'Script';
    if (_mainTab == AdminMainTab.game) title = 'Game';
    if (_mainTab == AdminMainTab.chat) {
      if (_view == AdminView.dm) {
        title = 'DM: ${room.players[_activeId]?.name ?? ""}';
      } else if (_view == AdminView.watch) {
        final chat = room.privateChats[_activeId];
        if (chat == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _backToChatMain();
          });
          title = 'Watching';
        } else {
          final names = chat.participants
              .map((id) => room.players[id]?.name ?? '?')
              .join(', ');
          title = 'Watching: $names';
        }
      } else if (_view == AdminView.neighborWatch) {
        final key = _activeNeighborKey;
        title = key == null
            ? 'Neighbor DM'
            : 'Watching: ${neighborPairLabel(room, key)}';
      }
    }

    final isChatSubView =
        _mainTab == AdminMainTab.chat && _view != AdminView.main;

    return AppBar(
      leading: isChatSubView
          ? IconButton(
              icon: const Icon(Icons.close), onPressed: _backToChatMain)
          : null,
      automaticallyImplyLeading: isChatSubView,
      title: Text(title),
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.black.withOpacity(0.18)),
        ),
      ),
    );
  }

  Widget _buildBottomNav(GameProvider provider, RoomState room) {
    final chatUnread = provider.unreadNeighborDmKeys.length;
    final playersUnread =
        room.pendingRequests.length + provider.unreadDmPlayerIds.length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const HairlineStrip(),
        NavigationBar(
          selectedIndex: _mainTab.index,
          onDestinationSelected: (i) {
            _unfocusAll();
            setState(() => _mainTab = AdminMainTab.values[i]);
          },
          destinations: [
            NavigationDestination(
              icon: _badgedIcon(Icons.chat_bubble_outline, chatUnread),
              label: 'Chat',
            ),
            NavigationDestination(
              icon: _badgedIcon(Icons.groups_outlined, playersUnread),
              label: 'Players',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Script',
            ),
            const NavigationDestination(
              icon: Icon(Icons.tune),
              label: 'Game',
            ),
          ],
        ),
      ],
    );
  }

  Widget _badgedIcon(IconData icon, int count) {
    if (count <= 0) return Icon(icon);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        Positioned(
          right: -6,
          top: -4,
          child: Container(
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
            decoration:
                const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
            child: Text('${count > 9 ? '9+' : count}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 9, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(GameProvider provider, RoomState room) {
    switch (_mainTab) {
      case AdminMainTab.chat:
        return _buildChatBody(provider, room);
      case AdminMainTab.players:
        return AdminPlayersTab(onOpenDm: openDm);
      case AdminMainTab.script:
        return const AdminScriptTab();
      case AdminMainTab.game:
        return AdminGameTab(
          onOpenWatch: openWatch,
          onOpenNeighborWatch: openNeighborWatch,
        );
    }
  }

  Widget _buildChatBody(GameProvider provider, RoomState room) {
    switch (_view) {
      case AdminView.main:
        return _ChatBody(
          messages: provider.mainChatMessages,
          controller: _mainController,
          focusNode: _mainFocus,
          onSend: (t, reply) => provider.adminSendMain(t, replyTo: reply),
          replySelection: _mainReply,
          recordingVoice: _recordingVoice,
          voiceElapsed: _voiceRecorder.elapsed,
          onVoicePressed: () => _toggleVoice(provider),
          onVoiceCancel: _cancelVoice,
          muted: false,
          currentUserId: 'admin',
          backgroundAsset: 'assets/images/general_chat.png',
          players: room.players,
        );
      case AdminView.dm:
        final player = room.players[_activeId];
        return _ChatBody(
          messages: player?.dmThread ?? [],
          controller: _dmController,
          focusNode: _dmFocus,
          onSend: (t, reply) =>
              provider.adminSendDm(_activeId!, t, replyTo: reply),
          replySelection: _dmReply,
          recordingVoice: _recordingVoice,
          voiceElapsed: _voiceRecorder.elapsed,
          onVoicePressed: () => _toggleVoice(provider),
          onVoiceCancel: _cancelVoice,
          muted: false,
          currentUserId: 'admin',
          backgroundAsset: 'assets/images/storyteller.png',
          players: room.players,
        );
      case AdminView.watch:
        final chat = room.privateChats[_activeId];
        return _WatchView(
          messages: chat?.messages ?? [],
          backgroundAsset: 'assets/images/private_chat.png',
          players: room.players,
        );
      case AdminView.neighborWatch:
        final key = _activeNeighborKey;
        final messages = key == null
            ? const <ChatMessage>[]
            : (room.neighborDmThreads[key] ?? const []);
        return _WatchView(
          messages: messages,
          backgroundAsset: 'assets/images/private_chat.png',
          players: room.players,
        );
    }
  }

  Future<void> _toggleVoice(GameProvider provider) async {
    if (_recordingVoice.value) {
      await _finishVoice(provider);
    } else {
      final started = await _voiceRecorder.start(
        onLimitReached: () => _finishVoice(provider),
      );
      if (!mounted) return;
      _recordingVoice.value = started;
      if (!started) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Microphone permission is required.')));
      }
    }
  }

  Future<void> _finishVoice(GameProvider provider) async {
    if (!_recordingVoice.value) return;
    final durationMs = _voiceRecorder.elapsed.value.inMilliseconds;
    final path = await _voiceRecorder.stop();
    _recordingVoice.value = false;
    if (path == null || !mounted) return;
    final bytes = await File(path).readAsBytes();
    if (_view == AdminView.dm && _activeId != null) {
      provider.adminSendDm(_activeId!, '',
          voiceBase64: base64Encode(bytes),
          durationMs: durationMs,
          replyTo: _dmReply.value);
      _dmReply.value = null;
    } else {
      provider.adminSendMainVoiceMessage(base64Encode(bytes),
          durationMs: durationMs, replyTo: _mainReply.value);
      _mainReply.value = null;
    }
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _cancelVoice() async {
    if (!_recordingVoice.value) return;
    await _voiceRecorder.cancel();
    _recordingVoice.value = false;
  }
}

/* ---------------------------------------------------------------------
 * These two widgets are unchanged from the original admin_panel.dart —
 * kept here as-is. (They're byte-identical to lobby_screen.dart's
 * _ChatBody; dedup into a shared widget is a good follow-up but not
 * required for this restructure.)
 * ------------------------------------------------------------------- */

class _WatchView extends StatelessWidget {
  final List<ChatMessage> messages;
  final String backgroundAsset;
  final Map<String, Player> players;
  const _WatchView({
    required this.messages,
    required this.backgroundAsset,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
            image: AssetImage(backgroundAsset), fit: BoxFit.cover),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
                decoration:
                    BoxDecoration(color: Colors.black.withOpacity(0.55))),
          ),
          ListView.builder(
            padding: EdgeInsets.fromLTRB(8, topInset, 8, 8),
            reverse: true,
            itemCount: messages.length,
            itemBuilder: (ctx, idx) {
              final msg = messages[messages.length - 1 - idx];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.78),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.bgCard,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.3),
                              blurRadius: 5,
                              offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (players[msg.senderId]?.alive == false)
                                const Padding(
                                  padding: EdgeInsets.only(right: 4),
                                  child: Text('💀',
                                      style: TextStyle(fontSize: 12)),
                                ),
                              Flexible(
                                child: Text(
                                  msg.senderName,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    color: Colors.amberAccent,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(msg.text,
                              style: const TextStyle(
                                  color: Colors.white, height: 1.3)),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ChatBody extends StatelessWidget {
  final List<ChatMessage> messages;
  final TextEditingController controller;
  final FocusNode focusNode;
  final void Function(String, ChatMessage?) onSend;
  final ValueNotifier<ChatMessage?>? replySelection;
  final ValueNotifier<bool>? recordingVoice;
  final ValueNotifier<Duration>? voiceElapsed;
  final VoidCallback? onVoicePressed;
  final VoidCallback? onVoiceCancel;
  final bool muted;
  final String? currentUserId;
  final String backgroundAsset;
  final Map<String, Player> players;

  const _ChatBody({
    required this.messages,
    required this.controller,
    required this.focusNode,
    required this.onSend,
    this.replySelection,
    this.recordingVoice,
    this.voiceElapsed,
    this.onVoicePressed,
    this.onVoiceCancel,
    required this.muted,
    required this.currentUserId,
    required this.backgroundAsset,
    required this.players,
  });

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight + 8;
    return Container(
      decoration: BoxDecoration(
        image: DecorationImage(
            image: AssetImage(backgroundAsset), fit: BoxFit.cover),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: DecoratedBox(
                decoration:
                    BoxDecoration(color: Colors.black.withOpacity(0.55))),
          ),
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(0, topInset, 0, 8),
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (ctx, idx) {
                    final msg = messages[messages.length - 1 - idx];
                    final isMine =
                        currentUserId != null && msg.senderId == currentUserId;
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
                      child: SwipeReply(
                        isMine: isMine,
                        onReply: replySelection == null
                            ? null
                            : () => replySelection!.value = msg,
                        child: Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: msg.bluffs != null
                              ? BluffMessageBubble(
                                  bluffs: msg.bluffs!,
                                  senderName: msg.senderName)
                              : ConstrainedBox(
                                  constraints: BoxConstraints(
                                      maxWidth:
                                          MediaQuery.of(context).size.width *
                                              0.78),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: isMine
                                          ? AppColors.emeraldDim
                                          : AppColors.bgCard,
                                      borderRadius: BorderRadius.only(
                                        topLeft: const Radius.circular(16),
                                        topRight: const Radius.circular(16),
                                        bottomLeft:
                                            Radius.circular(isMine ? 16 : 4),
                                        bottomRight:
                                            Radius.circular(isMine ? 4 : 16),
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.3),
                                            blurRadius: 5,
                                            offset: const Offset(0, 2)),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: isMine
                                          ? CrossAxisAlignment.end
                                          : CrossAxisAlignment.start,
                                      children: [
                                        if (msg.replyToText != null)
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(6),
                                            margin: const EdgeInsets.only(
                                                bottom: 5),
                                            decoration: BoxDecoration(
                                              color: Colors.white
                                                  .withOpacity(0.10),
                                              border: const Border(
                                                  left: BorderSide(
                                                      color: Colors.amberAccent,
                                                      width: 3)),
                                            ),
                                            child: Text(
                                                '${msg.replyToSenderName ?? 'Message'}: ${msg.replyToText}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 11,
                                                    color: Colors.white70)),
                                          ),
                                        if (!isMine)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              if (players[msg.senderId]
                                                      ?.alive ==
                                                  false)
                                                const Padding(
                                                  padding:
                                                      EdgeInsets.only(right: 4),
                                                  child: Text('💀',
                                                      style: TextStyle(
                                                          fontSize: 12)),
                                                ),
                                              Text(
                                                msg.senderName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: Colors.amberAccent,
                                                ),
                                              ),
                                            ],
                                          ),
                                        const SizedBox(height: 2),
                                        if (msg.voiceBase64 != null)
                                          VoiceMessageBubble(
                                            key: ValueKey('voice_${msg.id}'),
                                            base64Audio: msg.voiceBase64!,
                                            durationMs: msg.voiceDurationMs,
                                            mimeType: msg.voiceMime,
                                            isMine: isMine,
                                          )
                                        else
                                          Text(msg.text,
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  height: 1.3)),
                                      ],
                                    ),
                                  ),
                                ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (replySelection != null)
                ValueListenableBuilder<ChatMessage?>(
                  valueListenable: replySelection!,
                  builder: (context, reply, _) => reply == null
                      ? const SizedBox.shrink()
                      : Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 8, 8, 4),
                          color: AppColors.bgCard,
                          child: Row(children: [
                            Expanded(
                              child: Text(
                                  'Replying to ${reply.senderName}: ${reply.text}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                            ),
                            IconButton(
                                onPressed: () => replySelection!.value = null,
                                icon: const Icon(Icons.close)),
                          ]),
                        ),
                ),
              Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      border: Border(
                          top: BorderSide(
                              color: Colors.white.withOpacity(0.15))),
                    ),
                    child: ValueListenableBuilder<bool>(
                      valueListenable:
                          recordingVoice ?? ValueNotifier<bool>(false),
                      builder: (context, recording, _) => Row(
                        children: [
                          Expanded(
                            child: recording
                                ? _RecordingStatus(
                                    elapsed: voiceElapsed,
                                    onCancel: onVoiceCancel,
                                  )
                                : TextField(
                                    controller: controller,
                                    focusNode: focusNode,
                                    enabled: !muted,
                                    style: const TextStyle(color: Colors.black),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white.withOpacity(0.25),
                                      hintText: muted
                                          ? 'You are muted'
                                          : 'Type a message...',
                                      hintStyle: const TextStyle(
                                          color: Colors.black54),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(20),
                                        borderSide: BorderSide.none,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 14, vertical: 10),
                                    ),
                                    onSubmitted: (t) {
                                      if (t.isNotEmpty && !muted) {
                                        onSend(t, replySelection?.value);
                                        replySelection?.value = null;
                                        controller.clear();
                                      }
                                    },
                                  ),
                          ),
                          const SizedBox(width: 6),
                          if (onVoicePressed != null)
                            IconButton(
                              tooltip:
                                  recording ? 'Send recording' : 'Record voice',
                              color: recording
                                  ? Colors.redAccent
                                  : Colors.amberAccent,
                              onPressed: onVoicePressed,
                              icon: Icon(recording ? Icons.stop : Icons.mic),
                            ),
                          if (!recording)
                            IconButton(
                              icon: const Icon(Icons.send),
                              onPressed: muted
                                  ? null
                                  : () {
                                      if (controller.text.isNotEmpty) {
                                        onSend(controller.text,
                                            replySelection?.value);
                                        replySelection?.value = null;
                                        controller.clear();
                                      }
                                    },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordingStatus extends StatelessWidget {
  const _RecordingStatus({this.elapsed, this.onCancel});

  final ValueNotifier<Duration>? elapsed;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.fiber_manual_record,
            color: Colors.redAccent, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: ValueListenableBuilder<Duration>(
            valueListenable: elapsed ?? ValueNotifier(Duration.zero),
            builder: (context, duration, _) => Text(
              'Recording 00:${duration.inSeconds.toString().padLeft(2, '0')}',
              style: const TextStyle(
                  color: Colors.redAccent, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Cancel recording',
          onPressed: onCancel,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

// ---------- Unified banner stack (replaces individual notice banners) ----------
class _BannerStack extends StatelessWidget {
  final void Function(String playerId) onOpenDm;
  const _BannerStack({required this.onOpenDm});
  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final top = MediaQuery.of(context).padding.top + 8;
    return Stack(
      children: [
        for (int i = 0; i < provider.bannerQueue.length; i++)
          Positioned(
            top: top + (i * 58.0),
            left: 8,
            child: _AutoDismissCard(
              notice: provider.bannerQueue[i],
              onExpire: () => provider.popBanner(provider.bannerQueue[i]),
              onOpenDm: onOpenDm,
            ),
          ),
      ],
    );
  }
}

class _AutoDismissCard extends StatefulWidget {
  final BannerNotice notice;
  final VoidCallback onExpire;
  final void Function(String playerId) onOpenDm;
  const _AutoDismissCard({
    required this.notice,
    required this.onExpire,
    required this.onOpenDm,
  });
  @override
  State<_AutoDismissCard> createState() => _AutoDismissCardState();
}

class _AutoDismissCardState extends State<_AutoDismissCard> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    final duration = widget.notice.kind == BannerKind.disconnect
        ? const Duration(seconds: 12)
        : const Duration(seconds: 6);
    _timer = Timer(duration, widget.onExpire);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDisconnect = widget.notice.kind == BannerKind.disconnect;
    final accent = isDisconnect ? Colors.redAccent : Colors.amber;
    return Dismissible(
      key: ObjectKey(widget.notice),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => widget.onExpire(),
      child: GestureDetector(
        onTap: () {
          widget.onExpire();
          final playerId = widget.notice.targetPlayerId;
          if (playerId != null) widget.onOpenDm(playerId);
          widget.notice.onTap?.call();
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            constraints: const BoxConstraints(maxWidth: 260),
            decoration: BoxDecoration(
              color: isDisconnect
                  ? Colors.red.withOpacity(0.18)
                  : AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: isDisconnect
                  ? Border.all(color: Colors.redAccent, width: 1.6)
                  : null,
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isDisconnect)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child:
                        Icon(Icons.wifi_off, color: Colors.redAccent, size: 18),
                  ),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(widget.notice.title,
                          style: TextStyle(
                              color: accent,
                              fontSize: isDisconnect ? 13.5 : 12,
                              fontWeight: FontWeight.w800)),
                      if (widget.notice.subtitle != null) ...[
                        const SizedBox(height: 2),
                        Text(widget.notice.subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 12.5)),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// -----------------------------------------------------------------------------
