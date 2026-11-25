import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/player.dart';
import '../widgets/countdown_banner.dart';
import '../widgets/bluff_message_bubble.dart';
import 'reveal_screen.dart';
import 'table_tab.dart';
import 'script_tab.dart';
import 'me_tab.dart';
import 'dart:async';
import '../widgets/character_picker_dialog.dart'
    show alignmentColor, alignmentLabel;
import '../widgets/character_avatar.dart';
import '../widgets/glow_popup.dart';
import '../widgets/character_ability_sheet.dart';
import '../services/voice_recorder_service.dart';
import '../widgets/voice_message_bubble.dart';
import '../widgets/swipe_reply.dart';
import '../theme/app_theme.dart'; // NEW

enum MainTab { chat, table, script, me }

enum PlayerView { main, dm, private, neighborDm }

class LobbyScreen extends StatefulWidget {
  const LobbyScreen({super.key});
  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  MainTab _mainTab = MainTab.chat;
  PlayerView _view = PlayerView.main;
  String? _activeChatId;
  String? _activeNeighborPeerId;
  String? _returnToPrivateChatId; // NEW: peek marker

  final _mainController = TextEditingController();
  final _dmController = TextEditingController();
  final _privateController = TextEditingController();
  final _neighborController = TextEditingController();
  final _mainReply = ValueNotifier<ChatMessage?>(null);
  final _dmReply = ValueNotifier<ChatMessage?>(null);
  final _privateReply = ValueNotifier<ChatMessage?>(null);
  final _neighborReply = ValueNotifier<ChatMessage?>(null);
  final _recordingVoice = ValueNotifier<bool>(false);
  final _voiceRecorder = VoiceRecorderService();

  final _mainFocus = FocusNode();
  final _dmFocus = FocusNode();
  final _privateFocus = FocusNode();
  final _neighborFocus = FocusNode();

  String? _lastShownError;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _mainFocus.dispose();
    _dmFocus.dispose();
    _privateFocus.dispose();
    _neighborFocus.dispose();
    _mainReply.dispose();
    _dmReply.dispose();
    _privateReply.dispose();
    _neighborReply.dispose();
    _recordingVoice.dispose();
    _voiceRecorder.dispose();
    super.dispose();
  }

  void _unfocusAll() {
    _mainFocus.unfocus();
    _dmFocus.unfocus();
    _privateFocus.unfocus();
    _neighborFocus.unfocus();
  }

  void _openDm() {
    _unfocusAll();
    if (_view == PlayerView.private) _returnToPrivateChatId = _activeChatId;
    context.read<GameProvider>().openDmWithAdmin();
    setState(() {
      _mainTab = MainTab.chat;
      _view = PlayerView.dm;
    });
  }

  void _openNeighborDm(String peerId) {
    _unfocusAll();
    if (_view == PlayerView.private) _returnToPrivateChatId = _activeChatId;
    context.read<GameProvider>().openNeighborDm(peerId);
    setState(() {
      _mainTab = MainTab.chat;
      _view = PlayerView.neighborDm;
      _activeNeighborPeerId = peerId;
    });
  }

  void openPrivateChat(String chatId) {
    _unfocusAll();
    setState(() {
      _mainTab = MainTab.chat;
      _view = PlayerView.private;
      _activeChatId = chatId;
    });
  }

  void _backToMain() {
    _unfocusAll();
    _returnToPrivateChatId =
        null; // Clear peek marker if user manually navigates away
    context.read<GameProvider>().closeDmWithAdmin();
    context.read<GameProvider>().closeNeighborDm();
    setState(() {
      _view = PlayerView.main;
      _activeChatId = null;
      _activeNeighborPeerId = null;
    });
  }

  void _returnToPrivateChat() {
    _unfocusAll();
    if (_view == PlayerView.dm) context.read<GameProvider>().closeDmWithAdmin();
    if (_view == PlayerView.neighborDm) {
      context.read<GameProvider>().closeNeighborDm();
    }
    final chatId = _returnToPrivateChatId;
    _returnToPrivateChatId = null;
    if (chatId != null &&
        context.read<GameProvider>().privateChats.containsKey(chatId)) {
      setState(() {
        _view = PlayerView.private;
        _activeChatId = chatId;
      });
    } else {
      setState(() {
        _view = PlayerView.main;
        _activeChatId = null;
      });
    }
  }

  List<Widget> _neighborAppBarButtons(
      BuildContext context, GameProvider provider) {
    final room = provider.room;
    final myId = provider.myPlayer?.id;
    if (room == null || myId == null || room.seating.length < 2) return [];
    final neighbors = room.getNeighbors(myId);
    if (neighbors.isEmpty) return [];
    final ids = <String>[];
    for (final id in neighbors) {
      if (!ids.contains(id)) ids.add(id);
    }
    return [for (final peerId in ids) _neighborAppBarButton(provider, peerId)];
  }

  Widget _neighborAppBarButton(GameProvider provider, String peerId) {
    final peer = provider.room?.players[peerId];
    if (peer == null) return const SizedBox.shrink();
    final unread = provider.hasUnreadNeighborDm(peerId);
    return InkWell(
      onTap: () => _openNeighborDm(peerId),
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline, size: 20),
                if (unread)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 64),
              child: Text(peer.name,
                  style: const TextStyle(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }

  void _maybeShowError(GameProvider provider) {
    final err = provider.lastError;
    if (err == null || err == _lastShownError) return;
    _lastShownError = err;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(err), duration: const Duration(seconds: 4)),
      );
    });
  }

  void _showQueuedPopup(GamePopup popup, GameProvider provider) {
    switch (popup.type) {
      case GamePopupType.character:
        _showCharacterPopup(provider);
        break;
      case GamePopupType.bluffs:
        _showBluffsPopup(popup.characterIds ?? const [], provider);
        break;
      case GamePopupType.announcement:
        _showAnnouncementCard(popup.text ?? '');
        break;
      case GamePopupType.winner:
        showWinnerPopup(context, popup.alignment ?? 'good', onClosed: () {
          context.read<GameProvider>().popupClosed();
        });
        break;
    }
  }

  void _showCharacterPopup(GameProvider provider) {
    final character = provider.myCharacter;
    if (character == null) {
      provider.popupClosed();
      return;
    }
    final accent = alignmentColor(provider.myAlignment);
    showGlowPopup(
      context,
      accent: accent,
      icon: CharacterAvatar(character: character, radius: 28),
      eyebrow: alignmentLabel(provider.myAlignment).toUpperCase(),
      title: 'You are the ${character.name}',
      body: Column(
        children: [
          Text(
            character.ability.isEmpty
                ? 'No ability text available.'
                : character.ability,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 14.5, height: 1.45, color: Colors.white),
          ),
          if (character.flavor.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              character.flavor,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5,
                  fontStyle: FontStyle.italic,
                  color: Colors.white.withOpacity(0.55)),
            ),
          ],
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.black),
          onPressed: () {
            Navigator.pop(context);
            provider.popupClosed();
          },
          child: const Text('Got it'),
        ),
      ],
    );
  }

  void _showAnnouncementCard(String text) {
    const accent = Colors.amber;
    showGlowPopup(
      context,
      accent: accent,
      icon: const Icon(Icons.campaign, color: accent, size: 32),
      eyebrow: 'FROM THE STORYTELLER',
      title: text,
      actions: [
        OutlinedButton(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white70,
            side: const BorderSide(color: Colors.white24),
          ),
          onPressed: () {
            Navigator.pop(context);
            context.read<GameProvider>().popupClosed();
          },
          child: const Text('OK'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.black),
          icon: const Icon(Icons.reply, size: 18),
          label: const Text('Respond'),
          onPressed: () {
            Navigator.pop(context);
            context.read<GameProvider>().popupClosed();
            _maybeLeaveThenNavigate(_openDm);
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    _maybeShowError(provider);

    if (provider.myPlayer == null) {
      if (provider.wasDeclined) {
        return Scaffold(
          appBar: AppBar(title: const Text('Request Declined')),
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.block, size: 48, color: Colors.redAccent),
                  const SizedBox(height: 16),
                  const Text('The Storyteller declined your request to join.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      provider.acknowledgeDecline();
                      Navigator.of(context).pop();
                    },
                    child: const Text('Back'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Scaffold(
        appBar: AppBar(title: const Text('Waiting for host...')),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.hourglass_top, size: 48, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'Waiting for the Storyteller to approve you and assign a seat.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 8),
                Text('You can\'t send messages until you\'re seated.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13, color: Colors.grey)),
              ],
            ),
          ),
        ),
      );
    }
    final queuedPopup = provider.consumeNextPopup();
    if (queuedPopup != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showQueuedPopup(queuedPopup, provider);
      });
    }
    final chatLeftNotice = provider.consumeChatLeftNotice();
    if (chatLeftNotice != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(chatLeftNotice),
              duration: const Duration(seconds: 3)),
        );
      });
    }
    final pendingChatId = provider.pendingPrivateChatId;
    if (pendingChatId != null) {
      provider.clearPendingPrivateChat();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _unfocusAll();
        setState(() {
          _mainTab = MainTab.chat;
          _view = PlayerView.private;
          _activeChatId = pendingChatId;
        });
      });
    }

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
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldLeave = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: const Text('Leave the game?'),
                content:
                    const Text('You will be disconnected from this session.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: const Text('Stay')),
                  FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: Colors.redAccent),
                    onPressed: () => Navigator.of(dialogContext).pop(true),
                    child: const Text('Leave'),
                  ),
                ],
              ),
            ) ??
            false;
        if (!shouldLeave || !context.mounted) return;
        await context.read<GameProvider>().leaveGame();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: _buildAppBar(provider),
        body: Stack(
          children: [
            _buildBody(provider),
            const _PrivateRequestBanner(),
            const _JoinChatRequestBanner(),
            const CountdownFloatingCard(),
            const _DisconnectedStrip(),
            const _BannerStack(), // Replaces individual notice banners
          ],
        ),
        bottomNavigationBar: MediaQuery.of(context).viewInsets.bottom > 0
            ? null
            : _buildBottomNav(provider),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(GameProvider provider) {
    String title = 'General Chat';
    if (_mainTab == MainTab.table) title = 'Table';
    if (_mainTab == MainTab.script) title = 'Script';
    if (_mainTab == MainTab.me) title = 'Me';
    if (_mainTab == MainTab.chat) {
      if (_view == PlayerView.dm) title = 'Storyteller';
      if (_view == PlayerView.neighborDm) {
        final peer = provider.room?.players[_activeNeighborPeerId];
        title = peer?.name ?? 'Neighbor';
      }
      if (_view == PlayerView.private) {
        final chat = provider.privateChats[_activeChatId];
        if (chat != null) {
          final myId = provider.myPlayer?.id;
          final names = chat.participants
              .where((id) => id != myId)
              .map((id) => provider.room?.players[id]?.name ?? '?')
              .toList();
          title = names.isEmpty ? 'Private Chat' : 'Chat: ${names.join(', ')}';
        } else {
          title = 'Chat';
        }
      }
    }

    final isChatSubView = _mainTab == MainTab.chat && _view != PlayerView.main;
    final isPrivate = _mainTab == MainTab.chat && _view == PlayerView.private;
    final peeking = _returnToPrivateChatId != null;

    return AppBar(
      leading: isChatSubView && !isPrivate
          ? IconButton(
              icon: Icon(peeking ? Icons.arrow_back : Icons.close),
              onPressed: peeking ? _returnToPrivateChat : _backToMain,
            )
          : null,
      automaticallyImplyLeading: isChatSubView && !isPrivate,
      title: Text(title),
      backgroundColor: Colors.transparent,
      elevation: 0,
      flexibleSpace: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(color: Colors.black.withOpacity(0.18)),
        ),
      ),
      actions: [
        if (isPrivate)
          TextButton.icon(
            onPressed: () {
              provider.leavePrivateChat(_activeChatId!);
              _backToMain();
            },
            icon: const Icon(Icons.exit_to_app, color: Colors.white),
            label: const Text('Leave', style: TextStyle(color: Colors.white)),
          ),
        if (_mainTab == MainTab.chat && _view != PlayerView.dm)
          IconButton(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.chat_bubble_outline),
                if (provider.hasUnreadAdminDm)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: const BoxDecoration(
                          color: Colors.red, shape: BoxShape.circle),
                    ),
                  ),
              ],
            ),
            tooltip: 'Message the Storyteller',
            onPressed: _openDm,
          ),
        if (_mainTab == MainTab.chat &&
            (_view == PlayerView.main || _view == PlayerView.private))
          ..._neighborAppBarButtons(context, provider),
      ],
    );
  }

  Widget _buildBottomNav(GameProvider provider) {
    final unreadCount = (provider.hasUnreadAdminDm ? 1 : 0) +
        provider.unreadNeighborDmPeerIds.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const HairlineStrip(),
        NavigationBar(
          selectedIndex: _mainTab.index,
          onDestinationSelected: (i) {
            _unfocusAll();
            final tab = MainTab.values[i];
            setState(() => _mainTab = tab);
            if (tab == MainTab.me) {
              context.read<GameProvider>().markBluffsSeen();
            }
          },
          destinations: [
            NavigationDestination(
              icon: _badgedIcon(Icons.chat_bubble_outline, unreadCount),
              label: 'Chat',
            ),
            const NavigationDestination(
              icon: Icon(Icons.groups_outlined),
              label: 'Table',
            ),
            const NavigationDestination(
              icon: Icon(Icons.menu_book_outlined),
              label: 'Script',
            ),
            NavigationDestination(
              icon: _badgedIcon(
                  Icons.person_outline, provider.hasUnseenBluffs ? 1 : 0,
                  showCount: false),
              label: 'Me',
            ),
          ],
        ),
      ],
    );
  }

  Widget _badgedIcon(IconData icon, int count, {bool showCount = true}) {
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
            child: showCount
                ? Text('$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, color: Colors.white))
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildBody(GameProvider provider) {
    switch (_mainTab) {
      case MainTab.chat:
        return _buildChatBody(provider);
      case MainTab.table:
        return TableTab(onOpenPrivateChat: openPrivateChat);
      case MainTab.script:
        return const ScriptTab();
      case MainTab.me:
        return const MeTab();
    }
  }

  Widget _buildChatBody(GameProvider provider) {
    final players = provider.room?.players ?? {};
    switch (_view) {
      case PlayerView.main:
        return _ChatBody(
          messages: provider.mainChatMessages,
          controller: _mainController,
          focusNode: _mainFocus,
          onSend: (t, reply) => provider.sendMainMessage(t, replyTo: reply),
          replySelection: _mainReply,
          recordingVoice: _recordingVoice,
          voiceElapsed: _voiceRecorder.elapsed,
          onVoicePressed: () => _toggleVoice(provider),
          onVoiceCancel: _cancelVoice,
          muted: provider.myPlayer?.muted ?? false,
          currentUserId: provider.myPlayer?.id,
          backgroundAsset: 'assets/images/general_chat.png',
          players: players,
        );
      case PlayerView.dm:
        return _ChatBody(
          messages: provider.dmMessages['admin'] ?? [],
          controller: _dmController,
          focusNode: _dmFocus,
          onSend: (t, reply) => provider.sendDmMessage(t, replyTo: reply),
          replySelection: _dmReply,
          recordingVoice: _recordingVoice,
          voiceElapsed: _voiceRecorder.elapsed,
          onVoicePressed: () => _toggleVoice(provider),
          onVoiceCancel: _cancelVoice,
          muted: false,
          currentUserId: provider.myPlayer?.id,
          backgroundAsset: 'assets/images/storyteller.png',
          players: players,
        );
      case PlayerView.neighborDm:
        final peerId = _activeNeighborPeerId;
        if (peerId == null) {
          return const Center(child: Text('No neighbor selected'));
        }
        return _ChatBody(
          messages: provider.neighborDmMessages[peerId] ?? [],
          controller: _neighborController,
          focusNode: _neighborFocus,
          onSend: (t, reply) =>
              provider.sendNeighborDmMessage(peerId, t, replyTo: reply),
          replySelection: _neighborReply,
          recordingVoice: _recordingVoice,
          voiceElapsed: _voiceRecorder.elapsed,
          onVoicePressed: () => _toggleVoice(provider),
          onVoiceCancel: _cancelVoice,
          muted: false,
          currentUserId: provider.myPlayer?.id,
          backgroundAsset: 'assets/images/private_chat.png',
          players: players,
        );
      case PlayerView.private:
        final chat = provider.privateChats[_activeChatId];
        if (chat == null) return const Center(child: Text('Chat ended'));
        return _ChatBody(
          messages: chat.messages,
          controller: _privateController,
          focusNode: _privateFocus,
          onSend: (t, reply) => provider.sendPrivateMessage(_activeChatId!, t,
              replyTo: reply),
          replySelection: _privateReply,
          recordingVoice: _recordingVoice,
          voiceElapsed: _voiceRecorder.elapsed,
          onVoicePressed: () => _toggleVoice(provider),
          onVoiceCancel: _cancelVoice,
          muted: provider.myPlayer?.muted ?? false,
          currentUserId: provider.myPlayer?.id,
          backgroundAsset: 'assets/images/private_chat.png',
          players: players,
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
    final reply = switch (_view) {
      PlayerView.dm => _dmReply.value,
      PlayerView.private => _privateReply.value,
      PlayerView.neighborDm => _neighborReply.value,
      PlayerView.main => _mainReply.value,
    };
    switch (_view) {
      case PlayerView.main:
        provider.sendMainVoiceMessage(base64Encode(bytes),
            durationMs: durationMs, replyTo: reply);
        break;
      case PlayerView.dm:
        provider.sendDmMessage('',
            voiceBase64: base64Encode(bytes),
            durationMs: durationMs,
            replyTo: reply);
        break;
      case PlayerView.private:
        provider.sendPrivateMessage(_activeChatId!, '',
            voiceBase64: base64Encode(bytes),
            durationMs: durationMs,
            replyTo: reply);
        break;
      case PlayerView.neighborDm:
        provider.sendNeighborDmMessage(_activeNeighborPeerId!, '',
            voiceBase64: base64Encode(bytes),
            durationMs: durationMs,
            replyTo: reply);
        break;
    }
    _mainReply.value = null;
    _dmReply.value = null;
    _privateReply.value = null;
    _neighborReply.value = null;
    try {
      await File(path).delete();
    } catch (_) {}
  }

  Future<void> _cancelVoice() async {
    if (!_recordingVoice.value) return;
    await _voiceRecorder.cancel();
    _recordingVoice.value = false;
  }

  Future<void> _maybeLeaveThenNavigate(VoidCallback navigate) async {
    if (_view == PlayerView.private && _activeChatId != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          final colors = Theme.of(dialogContext).colorScheme;
          return AlertDialog(
            backgroundColor: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side:
                  BorderSide(color: Colors.amber.withOpacity(0.6), width: 1.2),
            ),
            title: Text('Leave this private chat?',
                style: TextStyle(color: colors.onSurface)),
            content: Text(
              'Opening this conversation will leave your current private chat.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text('Stay',
                    style: TextStyle(color: colors.onSurfaceVariant)),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Leave & Go'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) return;
      if (!mounted) return;
      context.read<GameProvider>().leavePrivateChat(_activeChatId!);
      setState(() {
        _activeChatId = null;
      });
    }
    navigate();
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
    final colors = Theme.of(context).colorScheme;
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
                    BoxDecoration(color: colors.scrim.withOpacity(0.55))),
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
                                          ? colors.primary
                                          : colors.surface,
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
                                              color: colors.onSurface
                                                  .withOpacity(0.10),
                                              border: Border(
                                                  left: BorderSide(
                                                      color: colors.primary,
                                                      width: 3)),
                                            ),
                                            child: Text(
                                                '${msg.replyToSenderName ?? 'Message'}: ${msg.replyToText}',
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 11,
                                                    color: colors
                                                        .onSurfaceVariant)),
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
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                  color: colors.primary,
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
                                              style: TextStyle(
                                                  color: colors.onSurface,
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
                          color: colors.surface,
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
                      color: colors.surface.withOpacity(0.92),
                      border: Border(
                          top: BorderSide(
                              color: colors.outline.withOpacity(0.25))),
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
                                    style: TextStyle(color: colors.onSurface),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: colors.surface,
                                      hintText: muted
                                          ? 'You are muted'
                                          : 'Type a message...',
                                      hintStyle: TextStyle(
                                          color: colors.onSurfaceVariant),
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
                              color: recording ? colors.error : colors.primary,
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
    final colors = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(Icons.fiber_manual_record, color: colors.error, size: 14),
        const SizedBox(width: 8),
        Expanded(
          child: ValueListenableBuilder<Duration>(
            valueListenable: elapsed ?? ValueNotifier(Duration.zero),
            builder: (context, duration, _) => Text(
              'Recording 00:${duration.inSeconds.toString().padLeft(2, '0')}',
              style:
                  TextStyle(color: colors.error, fontWeight: FontWeight.w600),
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
  const _BannerStack();
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
            ),
          ),
      ],
    );
  }
}

class _AutoDismissCard extends StatefulWidget {
  final BannerNotice notice;
  final VoidCallback onExpire;
  const _AutoDismissCard({required this.notice, required this.onExpire});
  @override
  State<_AutoDismissCard> createState() => _AutoDismissCardState();
}

class _AutoDismissCardState extends State<_AutoDismissCard> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer(const Duration(seconds: 6), widget.onExpire);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ObjectKey(widget.notice),
      direction: DismissDirection.horizontal,
      onDismissed: (_) => widget.onExpire(),
      child: GestureDetector(
        onTap: () {
          widget.onExpire();
          widget.notice.onTap?.call();
        },
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: const BoxConstraints(maxWidth: 240),
            decoration: BoxDecoration(
              color: AppColors.bgCard,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3))
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.notice.title,
                    style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
                if (widget.notice.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(widget.notice.subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 12.5)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
// -----------------------------------------------------------------------------

// NEW: non-blocking incoming private-chat request — slides in from the
// top-left, minimal text, two circular accept/decline buttons. Never
// uses a modal barrier, so it can't interrupt whatever the player is
// doing. Auto-declines after 20s if ignored, so the requester's button
// (see TableTab) doesn't stay disabled forever.
class _PrivateRequestBanner extends StatefulWidget {
  const _PrivateRequestBanner();
  @override
  State<_PrivateRequestBanner> createState() => _PrivateRequestBannerState();
}

class _PrivateRequestBannerState extends State<_PrivateRequestBanner> {
  Timer? _timer;
  String? _shownForId;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(GameProvider provider, String requesterId) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      provider.declinePrivateChatRequest(requesterId);
    });
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.18),
          border: Border.all(color: color),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final requesterId = provider.incomingRequestFromId;
    final requesterName = provider.incomingRequestFromName;

    if (requesterId == null) {
      _timer?.cancel();
      _shownForId = null;
      return const SizedBox.shrink();
    }
    if (_shownForId != requesterId) {
      _shownForId = requesterId;
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _startTimer(provider, requesterId));
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 8,
      left: 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 220),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text('${requesterName ?? 'Someone'} · chat?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              _circleBtn(Icons.close, Colors.redAccent,
                  () => provider.declinePrivateChatRequest(requesterId)),
              const SizedBox(width: 6),
              _circleBtn(Icons.check, Colors.greenAccent,
                  () => provider.acceptPrivateChatRequest(requesterId)),
            ],
          ),
        ),
      ),
    );
  }
}

// NEW: incoming "someone wants to join your private chat" — same
// non-blocking treatment as _PrivateRequestBanner, stacked just below
// it so both can show at once without overlapping.
class _JoinChatRequestBanner extends StatefulWidget {
  const _JoinChatRequestBanner();
  @override
  State<_JoinChatRequestBanner> createState() => _JoinChatRequestBannerState();
}

class _JoinChatRequestBannerState extends State<_JoinChatRequestBanner> {
  Timer? _timer;
  String? _shownForKey;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startTimer(GameProvider provider, String chatId, String requesterId) {
    _timer?.cancel();
    _timer = Timer(const Duration(seconds: 20), () {
      if (!mounted) return;
      provider.declineJoinChat(chatId, requesterId);
    });
  }

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.18),
          border: Border.all(color: color),
        ),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final chatId = provider.incomingJoinChatId;
    final requesterId = provider.incomingJoinRequesterId;
    final requesterName = provider.incomingJoinRequesterName;

    if (chatId == null || requesterId == null) {
      _timer?.cancel();
      _shownForKey = null;
      return const SizedBox.shrink();
    }
    final key = '$chatId|$requesterId';
    if (_shownForKey != key) {
      _shownForKey = key;
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _startTimer(provider, chatId, requesterId));
    }

    return Positioned(
      top: MediaQuery.of(context).padding.top + 46,
      left: 8,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 220),
          decoration: BoxDecoration(
            color: AppColors.bgCard,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 10,
                  offset: const Offset(0, 3)),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Text('${requesterName ?? 'Someone'} · join?',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 6),
              _circleBtn(Icons.close, Colors.redAccent,
                  () => provider.declineJoinChat(chatId, requesterId)),
              const SizedBox(width: 6),
              _circleBtn(Icons.check, Colors.greenAccent,
                  () => provider.acceptJoinChat(chatId, requesterId)),
            ],
          ),
        ),
      ),
    );
  }
}

class _DisconnectedStrip extends StatelessWidget {
  const _DisconnectedStrip();
  @override
  Widget build(BuildContext context) {
    final show = context.watch<GameProvider>().showDisconnectedBanner;
    if (!show) return const SizedBox.shrink();
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Material(
        color: Colors.redAccent.withOpacity(0.9),
        child: const SafeArea(
          bottom: false,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white)),
                SizedBox(width: 8),
                Text('You\'re disconnected — reconnecting…',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

extension _BluffsPopupExt on _LobbyScreenState {
  void _showBluffsPopup(List<String> characterIds, GameProvider provider) {
    const accent = Colors.amber;
    showGlowPopup(
      context,
      accent: accent,
      icon: const Icon(Icons.casino, color: accent, size: 30),
      eyebrow: 'FROM THE STORYTELLER',
      title: 'These are your bluffs',
      subtitle: 'Characters that are not currently in this game.',
      body: Wrap(
        spacing: 10,
        runSpacing: 10,
        alignment: WrapAlignment.center,
        children: [
          for (final id in characterIds)
            _BluffChip(characterId: id, provider: provider)
        ],
      ),
      actions: [
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: accent, foregroundColor: Colors.black),
          onPressed: () {
            Navigator.pop(context);
            provider.popupClosed();
          },
          child: const Text('Got it'),
        ),
      ],
    );
  }
}

class _BluffChip extends StatelessWidget {
  final String characterId;
  final GameProvider provider;
  const _BluffChip({required this.characterId, required this.provider});
  @override
  Widget build(BuildContext context) {
    final character = provider.characterById(characterId);
    if (character == null) return const SizedBox.shrink();
    return GestureDetector(
      onTap: () {
        Navigator.pop(context);
        provider.popupClosed();
        showCharacterAbilitySheet(context, character);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CharacterAvatar(character: character, radius: 22),
          const SizedBox(height: 4),
          Text(character.name,
              style: const TextStyle(fontSize: 11, color: Colors.white)),
        ],
      ),
    );
  }
}
