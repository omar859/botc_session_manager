import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/player.dart';
import '../models/private_chat.dart';
import '../models/room_state.dart';
import '../models/script_character.dart';
import '../models/message_types.dart';
import '../services/host_server.dart';
import '../services/script_library.dart';
import '../services/socket_client.dart';
import '../services/cloudflare_relay_client.dart';
import '../services/relay_bridge.dart';
import '../relay_config.dart';
import '../services/sound_service.dart';

// NEW: unified popup queue — character reveal, Storyteller
// announcements, and the winner declaration all funnel through this
// single queue instead of three independent flags, so two events
// landing in the same frame show one after another instead of one
// silently getting dropped or two dialogs stacking at once.
enum GamePopupType { character, announcement, winner, bluffs }

class GamePopup {
  final GamePopupType type;
  final String? text;
  final String? alignment;
  final List<String>? characterIds;
  const GamePopup._(this.type, {this.text, this.alignment, this.characterIds});
  factory GamePopup.character() => const GamePopup._(GamePopupType.character);
  factory GamePopup.announcement(String text) =>
      GamePopup._(GamePopupType.announcement, text: text);
  factory GamePopup.winner(String alignment) =>
      GamePopup._(GamePopupType.winner, alignment: alignment);
  factory GamePopup.bluffs(List<String> characterIds) =>
      GamePopup._(GamePopupType.bluffs, characterIds: characterIds);
}

// NEW: unified banner queue replacing the four separate notice lists.
enum BannerKind {
  privateRequest,
  joinRequest,
  neighborMsg,
  adminDmToPlayer,
  disconnect
}

class BannerNotice {
  final BannerKind kind;
  final String title;
  final String? subtitle;
  final String? targetPlayerId;
  final VoidCallback? onTap;
  BannerNotice(
      {required this.kind,
      required this.title,
      this.subtitle,
      this.targetPlayerId,
      this.onTap});
}

class GameProvider extends ChangeNotifier with WidgetsBindingObserver {
  HostServer? _hostServer;
  RoomState? _room;
  String _hostIp = '';
  int _hostPort = 0;

  GameClientTransport? _client;
  RelayBridge? _relayBridge;
  String? _myPlayerId;
  Player? _myPlayer;
  String? _persistentPlayerId;
  String? _myName;
  bool _isJoining = false;
  bool _showDisconnectedBanner = false;
  bool get showDisconnectedBanner => _showDisconnectedBanner;
  bool _bluffsInitialized = false;
  Timer? _reconnectLoopTimer; // NEW: persistent reconnect loop

  // NEW: small local cache for character data that isn't part of the
  // current script's broadcast list — populated whenever this device
  // learns the full ability/flavor of an off-script or custom
  // character, either because THIS device just assigned it (host) or
  // received it in a character_assigned/reveal_card_opened message
  // (a player). characterById checks this before giving up and
  // returning the empty placeholder.
  final Map<String, ScriptCharacter> _extraCharacterCache = {};
  void registerKnownCharacter(ScriptCharacter character) {
    _extraCharacterCache[character.id] = character;
  }

  void _handleSocketDisconnected() {
    if (_myPlayerId == null) return;
    _showDisconnectedBanner = true;
    notifyListeners();
    _startReconnectLoop();
  }

  // NEW: keeps retrying every 3s until it actually succeeds, instead
  // of a single one-shot attempt. Covers the real-world case of a
  // brief WiFi drop while the app stays open in the foreground — the
  // old code only ever retried once, then gave up silently.
  void _startReconnectLoop() {
    _reconnectLoopTimer?.cancel();
    _reconnectLoopTimer =
        Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (_client == null || _persistentPlayerId == null) {
        timer.cancel();
        _reconnectLoopTimer = null;
        return;
      }
      // FIX: don't open a redundant second socket if one is already
      // live — the old loop called connect() unconditionally every
      // tick, which is exactly what made the underlying race in
      // SocketClient easy to trigger. Once a socket is open, we just
      // wait for reconnect_success/reconnect_failed to arrive on it.
      if (_client!.isConnected) return;
      final connected = await _client!.connect();
      if (connected) {
        _client!.send(
            {'type': MessageType.reconnect, 'playerId': _persistentPlayerId});
      }
    });
  }

  bool _newGameJustStarted = false;
  bool consumeNewGameStarted() {
    if (!_newGameJustStarted) return false;
    _newGameJustStarted = false;
    return true;
  }

  void startNewGame() {
    _hostServer?.startNewGame();
    _resetForNewGame();
    notifyListeners();
  }

  void _resetForNewGame() {
    winnerAlignment = null;
    revealAssignments = null;
    _popupQueue.clear();
    _popupShowing = false;
    mainChatMessages.clear();
    dmMessages.clear();
    privateChats.clear();
    chatMembership.clear();
    neighborDmMessages.clear();
    unreadDmPlayerIds.clear();
    unreadNeighborDmKeys.clear();
    unreadNeighborDmPeerIds.clear();
    hasUnreadAdminDm = false;
    _openDmPlayerId = null;
    _openNeighborWatchKey = null;
    _openNeighborDmPeerId = null;
    _viewingDmWithAdmin = false;
    _watchedChatId = null;
    pendingPrivateChatId = null;
    pendingOutgoingRequestId = null;
    incomingRequestFromId = null;
    incomingRequestFromName = null;
    incomingJoinChatId = null;
    incomingJoinRequesterId = null;
    incomingJoinRequesterName = null;
    chatLeftNotices.clear();
    bannerQueue.removeWhere((notice) =>
        notice.kind == BannerKind.privateRequest ||
        notice.kind == BannerKind.adminDmToPlayer ||
        notice.kind == BannerKind.neighborMsg ||
        notice.kind == BannerKind.joinRequest);
    draftAssignments.clear();
    myCharacterId = null;
    myAlignment = null;
    myBluffs = [];
    hasUnseenBluffs = false;
    _bluffsInitialized = false;
    isNight = false;
    dayNumber = 1;
    countdownEndTime = null;
    SoundService.instance.stopAlarm();
    _extraCharacterCache.clear();
    _room?.isNight = false;
    _room?.dayNumber = 1;
    _room?.revealOrder = [];
    _room?.revealedCardIds = {};
    _room?.revealedCharacterIds = {};
    _room?.revealedAlignments = {};
    _newGameJustStarted = true;
    newGameGeneration++;
  }

  // NEW: unified banner queue
  final List<BannerNotice> bannerQueue = [];
  void pushBanner(BannerNotice n) {
    bannerQueue.add(n);
    notifyListeners();
  }

  void popBanner(BannerNotice n) {
    bannerQueue.remove(n);
    notifyListeners();
  }

  final List<String> chatLeftNotices = [];
  String? consumeChatLeftNotice() {
    if (chatLeftNotices.isEmpty) return null;
    return chatLeftNotices.removeAt(0);
  }

  // NEW: tracks retry attempts for a reconnect that initially failed —
  // see the reconnect_failed handling in _onClientMessage for why this
  // matters (the host takes up to ~12s to notice an earlier disconnect).
  int _reconnectRetries = 0;
  static const int _maxReconnectRetries = 5;

  List<ChatMessage> mainChatMessages = [];
  Map<String, List<ChatMessage>> dmMessages = {};
  Map<String, PrivateChat> privateChats = {};
  // NEW: public membership map — chatId -> list of participant playerIds.
  // This is broadcast to EVERYONE on any membership change, so the
  // Table tab can show who is busy/in a private chat even for players
  // not in that specific chat.
  final Map<String, List<String>> chatMembership = {};
  List<List<String>> myBluffs = [];
  List<String> scriptImageUrls = [];
  bool hasUnseenBluffs = false;
  void markBluffsSeen() {
    if (hasUnseenBluffs) {
      hasUnseenBluffs = false;
      notifyListeners();
    }
  }

  // NEW: direct, permission-less neighbor-to-neighbor DM threads, keyed
  // by the OTHER player's id (peerId) — mirrors dmMessages' shape (keyed
  // by 'admin') but there can be up to two per player (left + right).
  Map<String, List<ChatMessage>> neighborDmMessages = {};
  final Set<String> unreadNeighborDmPeerIds = {};
  String? _openNeighborDmPeerId;

  bool hasUnreadNeighborDm(String peerId) =>
      unreadNeighborDmPeerIds.contains(peerId);

  void openNeighborDm(String peerId) {
    _openNeighborDmPeerId = peerId;
    if (unreadNeighborDmPeerIds.remove(peerId)) {
      notifyListeners();
    }
  }

  void closeNeighborDm() {
    _openNeighborDmPeerId = null;
  }

  void sendNeighborDmMessage(String peerId, String text,
          {ChatMessage? replyTo,
          String? voiceBase64,
          int? durationMs,
          String? voiceMime}) =>
      _client?.send({
        'type': MessageType.neighborDmMessage,
        'targetId': peerId,
        'text': text,
        if (replyTo != null) ...{
          'replyToId': replyTo.id,
          'replyToSenderName': replyTo.senderName,
          'replyToText': replyTo.text,
        },
        if (voiceBase64 != null) 'voiceBase64': voiceBase64,
        if (durationMs != null) 'voiceDurationMs': durationMs,
        if (voiceMime != null) 'voiceMime': voiceMime,
      });

  // NEW: set the instant a private chat becomes mine to be IN — a fresh
  // 1-on-1 accept, my own join_chat_request being accepted, or landing
  // back in one after a reconnect. LobbyScreen consumes this exactly
  // once to teleport straight into that chat instead of leaving the
  // player to notice and navigate there manually.
  String? pendingPrivateChatId;

  void clearPendingPrivateChat() {
    pendingPrivateChatId = null;
  }

  String? _watchedChatId;
  String? get watchedChatId => _watchedChatId;

  // NEW: host-side unread indicator for player -> storyteller DMs. A
  // playerId sits in this set from the moment a DM arrives from that
  // player until the storyteller opens that DM thread (see openDm()).
  // _openDmPlayerId tracks which DM thread (if any) is currently on
  // screen, so a message that arrives while the storyteller is already
  // looking at that thread doesn't get flagged unread.
  final Set<String> unreadDmPlayerIds = {};
  String? _openDmPlayerId;

  bool hasUnreadDm(String playerId) => unreadDmPlayerIds.contains(playerId);

  void openDm(String playerId) {
    _openDmPlayerId = playerId;
    if (unreadDmPlayerIds.remove(playerId)) {
      notifyListeners();
    }
  }

  void closeDm() {
    _openDmPlayerId = null;
  }

  // NEW: storyteller-only oversight of neighbor-to-neighbor DMs — the
  // permission-less channel is player-to-player, but everything sent
  // through it still needs to reach the storyteller, same principle as
  // every other channel in this app. Read-only by design: there's no
  // "send" counterpart here, only watch/stopWatching, mirroring
  // watchChat/stopWatchingChat for regular private chats. Full history
  // lives in RoomState.neighborDmThreads already (host-authoritative);
  // these two fields only track which thread (if any) is currently on
  // screen, for the unread-dot logic.
  final Set<String> unreadNeighborDmKeys = {};
  String? _openNeighborWatchKey;

  bool hasUnreadNeighborDmThread(String key) =>
      unreadNeighborDmKeys.contains(key);

  void watchNeighborDm(String key) {
    _openNeighborWatchKey = key;
    if (unreadNeighborDmKeys.remove(key)) {
      notifyListeners();
    }
  }

  void stopWatchingNeighborDm() {
    _openNeighborWatchKey = null;
  }

  // NEW: client-side mirror of the above — a player's own unread flag for
  // the one DM thread they have (with the Storyteller). Set true when a
  // dm_message arrives from the Storyteller while the player isn't
  // currently looking at that thread; cleared by openDmWithAdmin().
  bool hasUnreadAdminDm = false;
  bool _viewingDmWithAdmin = false;

  void openDmWithAdmin() {
    _viewingDmWithAdmin = true;
    if (hasUnreadAdminDm) {
      hasUnreadAdminDm = false;
      notifyListeners();
    }
  }

  void closeDmWithAdmin() {
    _viewingDmWithAdmin = false;
  }

  String? incomingRequestFromId;
  String? incomingRequestFromName;
  // NEW: the one player (if any) this device has an outstanding
  // outgoing private-chat request to. Disables the "Private chat"
  // button for that player until it resolves or times out, so a tap
  // can't be spammed into duplicate requests.
  // (Replaced the two separate Sets with a single lock — one request at a time.)
  String? pendingOutgoingRequestId; // targetId OR chatId — whichever is pending
  bool get hasAnyPendingRequest => pendingOutgoingRequestId != null;

  // NEW: whether this device is already inside a private chat (as a
  // participant). While true, no new private/join requests can be sent —
  // accept-cancels-all also means being in a chat blocks initiating another.
  // MODIFIED: now uses the public chatMembership map instead of the
  // participant-only privateChats map, so the busy status is visible
  // even if this device didn't receive the private_chat_created event
  // (e.g., after reconnecting without the sync).
  bool get isInAnyPrivateChat =>
      _myPlayerId != null &&
      chatMembership.values.any((p) => p.contains(_myPlayerId));

  // NEW: chatIds this device is currently waiting on a join approval for.
  // (Removed — unified into pendingOutgoingRequestId above.)
  String? incomingJoinChatId;
  String? incomingJoinRequesterId;
  String? incomingJoinRequesterName;

  String? lastError;
  bool neighborRestriction = false;
  bool wasDeclined = false;

  // Private per-device notes one PLAYER keeps about another player (e.g.
  // "claimed Chambermaid", "poisoned"). Deliberately local-only, same as
  // characterGuesses below — these are personal suspicions/strategy notes
  // and must never reach the storyteller or any other player. This is NOT
  // used for the storyteller's own notes; see adminNotes below for those.
  Map<String, PlayerNote> playerNotes = {};

  PlayerNote getNoteFor(String playerId) =>
      playerNotes[playerId] ?? PlayerNote.empty;

  Future<void> setNoteFor(String playerId, PlayerNote note) async {
    if (note.isEmpty) {
      playerNotes.remove(playerId);
    } else {
      playerNotes[playerId] = note;
    }
    notifyListeners();
    await _savePlayerNotes();
  }

  // NEW: the storyteller's own notes about a player. Unlike playerNotes
  // above, these are host-authoritative — they live on the Player object
  // itself (Player.adminNotes) the same way dmThread does, are never
  // broadcast to anyone, and only make sense on the host device (there is
  // no socket message for this — see HostServer.setAdminNote).
  PlayerNote getAdminNoteFor(String playerId) =>
      _room?.players[playerId]?.adminNotes ?? PlayerNote.empty;

  void setAdminNoteFor(String playerId, PlayerNote note) {
    _hostServer?.setAdminNote(playerId, note);
    notifyListeners();
  }

  // Scoped to the current host address so notes from a past game don't
  // bleed into a new one, but survive an app restart mid-session (the
  // reconnect flow keeps the same _hostIp/_hostPort).
  String get _notesStorageKey => 'player_notes_${_hostIp}_$_hostPort';

  Future<void> _loadPlayerNotes() async {
    if (_hostIp.isEmpty || _hostPort == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_notesStorageKey);
    if (raw == null) {
      playerNotes = {};
    } else {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      playerNotes =
          decoded.map((k, v) => MapEntry(k, PlayerNote.fromDynamic(v)));
    }
    notifyListeners();
  }

  Future<void> _savePlayerNotes() async {
    if (_hostIp.isEmpty || _hostPort == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final Map<String, dynamic> serialized = {};
    playerNotes.forEach((k, v) => serialized[k] = v.toJson());
    await prefs.setString(_notesStorageKey, jsonEncode(serialized));
  }

  void declareWinner(String alignment) {
    _hostServer?.declareWinner(alignment);
    winnerAlignment = alignment;
    // The host doesn't receive its own broadcast — queue it locally too.
    _queuePopup(GamePopup.winner(alignment));
  }

  // NEW: private per-device GUESSES about other players' characters —
  // "I think they're the Empath". Same local-only treatment as notes:
  // never sent anywhere, just picked from the script's character list
  // instead of free text.
  Map<String, String> characterGuesses = {};

  String? getGuessFor(String playerId) => characterGuesses[playerId];

  Future<void> setGuessFor(String playerId, String? characterId) async {
    if (characterId == null || characterId.isEmpty) {
      characterGuesses.remove(playerId);
    } else {
      characterGuesses[playerId] = characterId;
    }
    notifyListeners();
    await _saveCharacterGuesses();
  }

  String get _guessesStorageKey => 'character_guesses_${_hostIp}_$_hostPort';

  Future<void> _loadCharacterGuesses() async {
    if (_hostIp.isEmpty || _hostPort == 0) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_guessesStorageKey);
    if (raw == null) {
      characterGuesses = {};
    } else {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      characterGuesses = decoded.map((k, v) => MapEntry(k, v as String));
    }
    notifyListeners();
  }

  Future<void> _saveCharacterGuesses() async {
    if (_hostIp.isEmpty || _hostPort == 0) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_guessesStorageKey, jsonEncode(characterGuesses));
  }

  // NEW: the storyteller's own character (this device's role, client-side
  // only — a storyteller has no character of their own).
  String? myCharacterId;
  // NEW: the queue itself. _popupShowing blocks handing out a second
  // popup while one is still on screen — the UI calls popupClosed()
  // when its dialog is dismissed, which lets the next one surface.
  final List<GamePopup> _popupQueue = [];
  bool _popupShowing = false;

  GamePopup? consumeNextPopup() {
    if (_popupShowing || _popupQueue.isEmpty) return null;
    _popupShowing = true;
    return _popupQueue.removeAt(0);
  }

  void popupClosed() {
    _popupShowing = false;
    if (_popupQueue.isNotEmpty) notifyListeners();
  }

  void _queuePopup(GamePopup popup) {
    _popupQueue.add(popup);
    notifyListeners();
  }

  // NEW: this device's own alignment, mirrored from the host's
  // set_player_alignment message. Only meaningful for a player (the
  // Storyteller has no character or alignment of their own).
  String? myAlignment;

  ScriptCharacter? characterById(String id) {
    if (id.isEmpty) return null;
    final chars = _room?.scriptCharacters ?? const <ScriptCharacter>[];
    for (final c in chars) {
      if (c.id == id) return c;
    }
    final known = _extraCharacterCache[id];
    if (known != null) return known;
    return ScriptCharacter(
      id: id,
      name: id,
      team: 'custom',
      ability: '(Custom character — no ability text on file.)',
    );
  }

  ScriptCharacter? get myCharacter =>
      myCharacterId == null ? null : characterById(myCharacterId!);
  // NEW: alignment for any player, from the Storyteller's point of
  // view — the host always has room.playerAlignments in full, since
  // it's the same RoomState object the server itself mutates.
  String alignmentFor(String playerId) =>
      _room?.playerAlignments[playerId] ?? 'good';

  // NEW: host-only staging area for character assignments before the
  // storyteller hits "Assign Characters" and sends them all at once —
  // see sendAssignments(). Never touches the network by itself.
  Map<String, String> draftAssignments = {};

  bool get hasPendingAssignments => draftAssignments.isNotEmpty;

  void setDraftAssignment(String playerId, String characterId) {
    draftAssignments[playerId] = characterId;
    notifyListeners();
  }

  void clearDraftAssignment(String playerId) {
    draftAssignments.remove(playerId);
    notifyListeners();
  }

  Future<void> sendAssignments() async {
    if (draftAssignments.isEmpty) return;
    _hostServer?.assignCharacters(Map<String, String>.from(draftAssignments));
    draftAssignments.clear();
    notifyListeners();
  }

  // NEW: assigns and sends a single character immediately, bypassing the
  // staged draftAssignments/sendAssignments flow above. That flow is for
  // the initial batch assignment at game start; this is for one-off
  // changes mid-game — most notably, handing a newly-joined player a
  // Traveller character without disturbing anyone else's assignment.
  void assignCharacterNow(String playerId, String characterId,
      {ScriptCharacter? characterData, String? alignment}) {
    _hostServer?.assignCharacterWithData(playerId, characterId, characterData,
        alignment: alignment);
    if (characterData != null) registerKnownCharacter(characterData);
    notifyListeners();
  }

  void sendAnnouncement(String text, List<String>? targetPlayerIds) {
    _hostServer?.sendAnnouncement(text, targetPlayerIds);
  }

  // NEW: change any player's alignment directly, no character
  // reassignment required.
  void setPlayerAlignment(String playerId, String alignment) {
    _hostServer?.setPlayerAlignment(playerId, alignment);
    notifyListeners();
  }

  // NEW: host imports a script JSON file exported from the script tool and
  // resolves it (official IDs + homebrew objects) into a broadcastable
  // character list.
  Future<bool> importScript() async {
    final result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    final path = result?.files.single.path;
    if (path == null) return false;

    try {
      final raw = await File(path).readAsString();
      final decoded = jsonDecode(raw) as List<dynamic>;
      final characters = await ScriptLibrary.instance.mergeScript(decoded);
      _hostServer?.setScriptCharacters(characters);
      notifyListeners();
      return true;
    } catch (e) {
      lastError = 'Could not read that script file. Make sure it\'s a '
          'script-tool JSON export.';
      notifyListeners();
      return false;
    }
  }

  DateTime? countdownEndTime;
  DateTime? _countdownAlarmFiredForEndTime;

  // NEW: called every tick by CountdownBanner. Tracking lives here
  // (not in the widget) so it survives the widget being torn down and
  // rebuilt when the player switches bottom-nav tabs.
  void maybeFireCountdownAlarm() {
    final end = countdownEndTime;
    if (end == null) {
      _countdownAlarmFiredForEndTime = null;
      return;
    }
    if (_countdownAlarmFiredForEndTime == end) return;
    if (DateTime.now().isAfter(end)) {
      _countdownAlarmFiredForEndTime = end;
      SoundService.instance.playAlarm();
    }
  }

  // NEW: manual stop, independent of cancelling the timer.
  void stopCountdownSound() {
    _hostServer?.stopCountdownSound();
    SoundService.instance.stopAlarm();
  }

  // NEW: current day/night phase, mirrored from RoomState on the host and
  // from the night_mode_change broadcast on clients. Read by NightOverlay
  // and the day/night sound listener on both the admin panel and lobby.
  bool isNight = false;
  int dayNumber = 1;

  // NEW: end-of-game character reveal. Non-null once a game_reveal arrives
  // — the chat screens watch this to push RevealScreen on top of themselves.
  // Each entry: {playerId, playerName, characterId}. Cleared by stopHosting.
  List<Map<String, dynamic>>? revealAssignments;
  String? winnerAlignment;
  int newGameGeneration = 0;
  int revealGeneration = 0;

  // NEW: tracks whether the reveal screen is currently open or has been
  // pushed. This lives in the provider instead of a local one-shot
  // flag inside LobbyScreen/AdminPanel so it resets correctly on every
  // new reveal, regardless of how the screen was dismissed.
  bool revealScreenOpen = false;
  void markRevealScreenOpen() => revealScreenOpen = true;
  void markRevealScreenClosed() {
    revealScreenOpen = false;
    notifyListeners();
  }

  // NEW: true once a reveal is in progress, host OR client. Host:
  // revealAssignments is populated immediately (the storyteller already
  // knows every assignment). Client: revealAssignments now stays null
  // forever — players never receive the full answer sheet up front — so
  // revealOrder arriving non-empty is what signals "reveal started"
  // instead. Both LobbyScreen and AdminPanel gate their "push
  // RevealScreen" logic on this one getter.
  bool get revealActive =>
      revealAssignments != null || (_room?.revealOrder.isNotEmpty ?? false);

  bool get isHost => _hostServer != null;
  bool get isOnlineHost => _relayBridge != null;
  bool get onlineActive => _relayBridge != null;
  bool get onlineConnected => _relayBridge?.connected.value ?? false;
  String? get onlineJoinUrl => _relayBridge?.joinUrl;
  RoomState? get room => _room;
  String get roomCode => _room?.roomCode ?? '';
  String get hostIp => _hostIp;
  int get hostPort => _hostPort;
  Player? get myPlayer => _myPlayer;

  bool get isClientConnected => _client != null && _client!.isConnected;

  GameProvider() {
    _loadPersistentId();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reconnectLoopTimer?.cancel();
    _reconnectLoopTimer = null;
    _relayBridge?.stop();
    _hostServer?.dispose();
    _client?.disconnect();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // NEW: a locked screen or incoming call can silently kill the
    // WebSocket without ever firing onDone/onError — the client-side
    // isConnected flag can't be trusted after a resume, so always
    // re-establish the connection fresh rather than checking it first.
    if (state == AppLifecycleState.resumed &&
        _client != null &&
        _persistentPlayerId != null) {
      _client!.disconnect();
      _client!.connect().then((connected) {
        if (connected) {
          _client!.send(
              {'type': MessageType.reconnect, 'playerId': _persistentPlayerId});
        }
      });
    }
  }

  // ───────── Host ─────────
  // NEW: network_info_plus needs a location permission grant to read the
  // WiFi IP on most Android versions. Without this, getWifiIP() can return
  // null and HostServer silently falls back to 127.0.0.1 — unreachable to
  // every other player, with no error shown anywhere. Requesting it here,
  // before the server starts, means a denial is caught immediately instead
  // of surfacing later as "nobody can connect."
  Future<bool> startHosting() async {
    final status = await Permission.locationWhenInUse.request();
    if (!status.isGranted) {
      lastError =
          'Location permission is needed to find this phone\'s WiFi address before hosting can start.';
      notifyListeners();
      return false;
    }

    _room = RoomState();
    _hostServer = HostServer(_room!);
    _hostServer!.events.listen(_onHostEvent);
    final addr = await _hostServer!.start();
    final parts = addr.split(':');
    _hostIp = parts[0];
    _hostPort = int.parse(parts[1]);
    await _loadPlayerNotes();
    await _loadCharacterGuesses();
    notifyListeners();
    return true;
  }

  Future<bool> startOnlineHosting() async {
    final started = await startHosting();
    if (!started) return false;
    final bridge = RelayBridge(relayHost: kRelayHost, localPort: _hostPort);
    _relayBridge = bridge;
    _room?.roomCode = bridge.roomCode;
    bridge.connected.addListener(notifyListeners);
    bridge.start();
    notifyListeners();
    return true;
  }

  void _onHostEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'server_started':
        _hostIp = event['ip'];
        _hostPort = event['port'];
        break;
      case 'player_disconnected_notice':
        pushBanner(BannerNotice(
          kind: BannerKind.disconnect,
          title: '⚠ ${event['playerName']} disconnected',
        ));
        break;
      case 'chat_message':
        mainChatMessages.add(ChatMessage.fromJson(event['message']));
        break;
      case 'dm_message':
        final playerId = event['playerId'] as String;
        final messageJson = event['message'] as Map<String, dynamic>;
        dmMessages
            .putIfAbsent(playerId, () => [])
            .add(ChatMessage.fromJson(messageJson));
        final senderId = messageJson['senderId'] as String?;
        if (senderId != null &&
            senderId != 'admin' &&
            _openDmPlayerId != playerId) {
          unreadDmPlayerIds.add(playerId);
          final senderName = (messageJson['senderName'] as String?) ?? 'Player';
          final text = (messageJson['text'] as String?) ?? '';
          pushBanner(BannerNotice(
            kind: BannerKind.privateRequest,
            title: senderName,
            subtitle: text,
            targetPlayerId: playerId,
          ));
        }
        break;
      case 'private_message':
        final chatId = event['chatId'];
        final chat = _room?.privateChats[chatId];
        if (chat != null) {
          chat.messages.add(ChatMessage.fromJson(event['message']));
        }
        break;
      case 'private_chat_ended':
      case 'all_private_chats_ended':
        _watchedChatId = null;
        break;
      case 'countdown_start':
        countdownEndTime = DateTime.parse(event['endsAt'] as String).toLocal();
        break;
      case 'countdown_cancel':
        countdownEndTime = null;
        break;
      case MessageType.nightModeChange:
        isNight = event['isNight'] == true;
        dayNumber = event['dayNumber'] as int? ?? dayNumber;
        break;
      case MessageType.gameReveal:
        revealAssignments = (event['assignments'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        revealGeneration++;
        break;
      case 'neighbor_dm_message':
        final key = event['key'] as String;
        if (_openNeighborWatchKey != key) {
          unreadNeighborDmKeys.add(key);
        }
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void approveJoinRequest(String playerId, [int? seat]) {
    _hostServer?.approveJoin(playerId, seat);
    notifyListeners();
  }

  void declineJoinRequest(String playerId) {
    _hostServer?.declineJoin(playerId);
    notifyListeners();
  }

  void kickPlayer(String playerId) {
    _hostServer?.kickPlayer(playerId);
    notifyListeners();
  }

  void swapPlayerSeats(String playerIdA, String playerIdB) {
    _hostServer?.swapPlayerSeats(playerIdA, playerIdB);
    notifyListeners();
  }

  void setChatMode(ChatMode mode) {
    _hostServer?.setChatMode(mode);
    notifyListeners();
  }

  void setNeighborRestriction(bool on) {
    _hostServer?.setNeighborRestriction(on);
    notifyListeners();
  }

  void mutePlayer(String playerId, bool mute) {
    _hostServer?.mutePlayer(playerId, mute);
    notifyListeners();
  }

  void forceCloseChat(String chatId) {
    _hostServer?.forceCloseChat(chatId);
    notifyListeners();
  }

  void forceCloseAllChats() {
    _hostServer?.forceCloseAllChats();
    notifyListeners();
  }

  void adminSendDm(String playerId, String text,
          {ChatMessage? replyTo,
          String? voiceBase64,
          int? durationMs,
          String? voiceMime}) =>
      _hostServer?.adminSendDm(playerId, text,
          replyTo: replyTo,
          voiceBase64: voiceBase64,
          durationMs: durationMs,
          voiceMime: voiceMime);

  // NEW: storyteller-only controls for BOTC status. Unlike mutePlayer
  // above, these call notifyListeners() directly — the host device
  // mutates the shared RoomState in place but isn't one of its own
  // WebSocket clients, so without this the storyteller's own screen
  // wouldn't refresh until some unrelated event happened to trigger one.
  void setPlayerAlive(String playerId, bool alive) {
    _hostServer?.setPlayerAlive(playerId, alive);
    notifyListeners();
  }

  void setGhostVoteUsed(String playerId, bool used) {
    _hostServer?.setGhostVoteUsed(playerId, used);
    notifyListeners();
  }

  void adminSendMain(String text, {ChatMessage? replyTo}) {
    _hostServer?.adminSendMain(text, replyTo: replyTo);
  }

  void addScriptImage(String filePath) {
    _hostServer?.addScriptImage(filePath);
    notifyListeners();
  }

  void removeScriptImage(String fileName) {
    _hostServer?.removeScriptImage(fileName);
    notifyListeners();
  }

  void watchChat(String chatId) {
    _watchedChatId = chatId;
    notifyListeners();
  }

  void stopWatchingChat() {
    _watchedChatId = null;
    notifyListeners();
  }

  void startCountdown(int seconds) {
    _hostServer?.startCountdown(seconds);
  }

  void cancelCountdown() {
    _hostServer?.cancelCountdown();
    _hostServer?.stopCountdownSound();
    SoundService.instance.stopAlarm();
  }

  // NEW: day/night toggle, end-of-game reveal, and storyteller bluffs.
  // All three are storyteller-only actions on the host. The resulting
  // state changes (isNight / revealAssignments) come back through
  // _onHostEvent on the host device, exactly the same way clients receive
  // them over the socket — so both screens can render against one source.
  void setNight(bool night) {
    _hostServer?.setNight(night);
    notifyListeners();
  }

  void revealGame() {
    _hostServer?.revealCharacters();
    notifyListeners();
  }

  // NEW: storyteller taps one card open on the reveal screen.
  void revealCard(String playerId) {
    _hostServer?.revealCard(playerId);
    notifyListeners();
  }

  void adminSendBluffs(List<String> characterIds, String targetPlayerId) {
    _hostServer?.adminSendBluffs(characterIds, targetPlayerId);
    notifyListeners();
  }

  // NEW: lets the storyteller delete one previously-sent bluff set for a
  // player (e.g. after correcting a mistaken claim). Calls notifyListeners
  // directly, the same way setPlayerAlive/setGhostVoteUsed above do —
  // the host mutates its own shared RoomState in place but isn't one of
  // its own WebSocket clients, so without this the storyteller's own
  // "Manage Bluffs" screen wouldn't refresh until some unrelated event
  // happened to trigger one.
  void deleteBluffSet(String playerId, int setIndex) {
    _hostServer?.removeBluffSet(playerId, setIndex);
    notifyListeners();
  }

  Future<void> stopHosting() async {
    _reconnectLoopTimer?.cancel();
    _reconnectLoopTimer = null;
    _relayBridge?.stop();
    _relayBridge = null;
    _hostServer?.dispose();
    _hostServer = null;
    _room = null;
    _hostIp = '';
    _hostPort = 0;
    countdownEndTime = null;
    isNight = false;
    revealAssignments = null;
    winnerAlignment = null;
    _popupQueue.clear();
    _popupShowing = false;
    bannerQueue.clear();
    mainChatMessages.clear();
    dmMessages.clear();
    privateChats.clear();
    chatMembership.clear(); // NEW: clear public membership map
    scriptImageUrls.clear();
    _watchedChatId = null;
    incomingRequestFromId = null;
    incomingRequestFromName = null;
    incomingJoinChatId = null;
    incomingJoinRequesterId = null;
    incomingJoinRequesterName = null;
    lastError = null;
    playerNotes = {};
    draftAssignments = {};
    unreadDmPlayerIds.clear();
    _openDmPlayerId = null;
    unreadNeighborDmKeys.clear();
    _openNeighborWatchKey = null;
    pendingOutgoingRequestId = null;
    _extraCharacterCache.clear();
    notifyListeners();
  }

  // NEW: client-side teardown when a player leaves from the RevealScreen's
  // "Leave Game" button. Mirrors the disconnect half of stopHosting (there
  // is no host server to dispose on this device) and also wipes the saved
  // session so this device won't offer "Resume Game" for a game that's
  // intentionally over. The caller (RevealScreen) is responsible for
  // navigating back to Home afterwards.
  Future<void> leaveGame() async {
    _reconnectLoopTimer?.cancel();
    _reconnectLoopTimer = null;
    neighborRestriction = false;
    _client?.disconnect();
    _client = null;
    _room = null;

    mainChatMessages.clear();
    dmMessages.clear();
    privateChats.clear();
    chatMembership.clear(); // NEW: clear public membership map
    pendingPrivateChatId = null;
    neighborDmMessages.clear();
    unreadNeighborDmPeerIds.clear();
    _openNeighborDmPeerId = null;
    isNight = false;
    revealAssignments = null;
    winnerAlignment = null;
    _popupQueue.clear();
    _popupShowing = false;
    bannerQueue.clear();
    countdownEndTime = null;
    _bluffsInitialized = false;
    myCharacterId = null;
    myAlignment = null;
    _myPlayerId = null;
    _myPlayer = null;
    incomingRequestFromId = null;
    incomingRequestFromName = null;
    incomingJoinChatId = null;
    incomingJoinRequesterId = null;
    incomingJoinRequesterName = null;
    pendingOutgoingRequestId = null;
    _extraCharacterCache.clear();
    await _clearPersistentSession();
    notifyListeners();
  }

  // ───────── Client ─────────
  Future<bool> joinGame(String ip, int port, String name) async {
    if (_isJoining || isClientConnected) return false;
    _isJoining = true;
    wasDeclined = false;
    myCharacterId = null;
    _myName = name;
    await _savePlayerName(name);
    _hostIp = ip;
    _hostPort = port;
    await _loadPlayerNotes();
    await _loadCharacterGuesses();

    _client = SocketClient(
      serverIp: ip,
      port: port,
      onMessage: _onClientMessage,
      onDisconnected: _handleSocketDisconnected,
    );
    const reconnectToken = null;

    final connected = await _client!.connect();
    if (!connected) {
      _client?.disconnect();
      _client = null;
      notifyListeners();
      _isJoining = false;
      return false;
    }

    if (reconnectToken == null) {
      // No saved identity for this host — this is a genuine first-time
      // join, so there's nothing to wait on.
      _client!.send({'type': 'join_request', 'name': name});
    } else {
      // FIX: this used to send join_request here UNCONDITIONALLY,
      // regardless of the reconnectToken above — meaning a returning
      // player's app already sent a 'reconnect' message (inside
      // connect()) and then immediately ALSO sent a brand new
      // join_request no matter what happened next. That could register
      // the same person twice: once correctly reconnected to their old
      // seat, and once as a fresh duplicate player, depending on timing.
      // Now we wait for reconnect_success/reconnect_failed instead — see
      // _onClientMessage.
      _reconnectRetries = 0;
    }
    _isJoining = false;
    notifyListeners();
    return true;
  }

  Future<bool> joinOnlineGame(String roomCode, String name) async {
    if (_isJoining || isClientConnected) return false;
    _isJoining = true;
    wasDeclined = false;
    myCharacterId = null;
    _myName = name;
    await _savePlayerName(name);
    await _loadPlayerNotes();
    await _loadCharacterGuesses();
    _client = CloudflareRelayClient(
      relayHost: kRelayHost,
      roomCode: roomCode,
      onMessage: _onClientMessage,
      onDisconnected: _handleSocketDisconnected,
    );
    final connected = await _client!.connect();
    if (!connected) {
      _client?.disconnect();
      _client = null;
      _isJoining = false;
      lastError = 'Online room not found or no longer available.';
      notifyListeners();
      return false;
    }
    _hostIp = 'Online';
    _hostPort = 0;
    _isJoining = false;
    notifyListeners();
    return true;
  }

  void acknowledgeDecline() {
    wasDeclined = false;
    notifyListeners();
  }

  void _onClientMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case 'announcement':
        final announcementText = msg['text'] as String?;
        if (announcementText != null && announcementText.isNotEmpty) {
          _queuePopup(GamePopup.announcement(announcementText));
        }
        break;
      case MessageType.neighborModeChange:
        neighborRestriction = msg['on'] == true;
        break;
      case 'join_pending':
        _myPlayerId = msg['playerId'];
        _savePersistentId(_myPlayerId!);
        break;
      case 'join_declined':
        wasDeclined = true;
        _client?.disconnect();
        _client = null;
        // The storyteller explicitly rejected this attempt — a clear
        // enough signal to stop offering to resume it.
        _clearPersistentSession();
        break;
      case 'new_game_started':
        _resetForNewGame();
        break;
      case 'join_approved':
        _myPlayerId = msg['playerId'];
        _bluffsInitialized = false;
        _showDisconnectedBanner = false;
        _savePersistentId(_myPlayerId!);
        _myPlayer = Player.fromJson({
          'id': msg['playerId'],
          'name': _myName ?? 'You',
          'seat': msg['seat']
        });
        _updateSeatingFromMsg(msg);
        break;
      case 'seating_update':
        _updateSeatingFromMsg(msg);
        break;
      case 'chat_message':
        mainChatMessages.add(ChatMessage.fromJson(msg['message']));
        break;
      case MessageType.fabledUpdate:
        _room ??= RoomState();
        _room!.activeFabled = (msg['characters'] as List)
            .map((c) => ScriptCharacter.fromJson(c as Map<String, dynamic>))
            .toList();
        for (final c in _room!.activeFabled) {
          registerKnownCharacter(c);
        }
        break;
      case 'dm_message':
        dmMessages
            .putIfAbsent('admin', () => [])
            .add(ChatMessage.fromJson(msg['message']));
        if (msg['fromAdmin'] == true && !_viewingDmWithAdmin) {
          hasUnreadAdminDm = true;
          final m = msg['message'] as Map<String, dynamic>;
          final text = (m['text'] as String?) ?? '';
          pushBanner(BannerNotice(
            kind: BannerKind.adminDmToPlayer,
            title: 'Storyteller',
            subtitle: text,
          ));
        }
        break;

      // NEW: storyteller's private bluff list, sent only to the target
      // player. Routed into the admin DM thread so it appears alongside
      // other storyteller messages — just rendered as tappable character
      // chips instead of plain text.
      case MessageType.bluffMessage:
        final newBluffs = (msg['bluffs'] as List<dynamic>)
            .map((set) => List<String>.from(set as List<dynamic>))
            .toList();
        if (newBluffs.length > myBluffs.length) hasUnseenBluffs = true;
        if (_bluffsInitialized && newBluffs.length > myBluffs.length) {
          for (var i = myBluffs.length; i < newBluffs.length; i++) {
            _queuePopup(GamePopup.bluffs(newBluffs[i]));
          }
        }
        myBluffs = newBluffs;
        _bluffsInitialized = true;
        break;

      case 'private_chat_request_received':
        incomingRequestFromId = msg['requesterId'];
        incomingRequestFromName = msg['requesterName'];
        break;
      case 'private_chat_request_declined':
        lastError = 'Your private chat request was declined.';
        pendingOutgoingRequestId = null;
        break;
      case 'private_chat_request_cancelled': // NEW — see item 7
        if (incomingRequestFromId == msg['requesterId']) {
          incomingRequestFromId = null;
          incomingRequestFromName = null;
        }
        break;
      case 'private_chat_created':
        _addPrivateChat(msg['chatId'], List<String>.from(msg['participants']));
        chatMembership[msg['chatId'] as String] =
            List<String>.from(msg['participants']); // NEW
        pendingPrivateChatId = msg['chatId'] as String;
        pendingOutgoingRequestId = null;
        break;

      case 'join_chat_request_received':
        incomingJoinChatId = msg['chatId'];
        incomingJoinRequesterId = msg['requesterId'];
        incomingJoinRequesterName = msg['requesterName'];
        break;
      case 'join_chat_declined':
        lastError = 'Your request to join the chat was declined.';
        pendingOutgoingRequestId = null;
        break;

      case 'participant_joined':
        {
          final chatId = msg['chatId'] as String;
          final participants = List<String>.from(msg['participants']);
          final newParticipantId = msg['newParticipantId'] as String?;
          pendingOutgoingRequestId = null;
          chatMembership[chatId] = participants; // NEW
          if (!privateChats.containsKey(chatId)) {
            _addPrivateChat(chatId, participants);
          } else {
            _updateParticipants(chatId, participants);
          }
          // FIX: teleport specifically when THIS player is the one who
          // was just added, using the host's authoritative
          // newParticipantId field — checking "was this chat new to
          // me" alone could silently miss firing if the chat entry
          // already existed in this map for any reason (e.g. a stale
          // leftover from a prior sync), which is the most likely
          // cause of "accepted but nothing happened" for the requester.
          if (newParticipantId != null && newParticipantId == _myPlayerId) {
            pendingPrivateChatId = chatId;
          }
        }
        break;
      case 'participant_left':
        _updateParticipants(msg['chatId'], msg['participants']);
        chatMembership[msg['chatId'] as String] =
            List<String>.from(msg['participants'] as List); // NEW
        final leftName = msg['leftPlayerName'] as String?;
        if (leftName != null) chatLeftNotices.add('$leftName left the chat');
        break;
      case 'private_message':
        final chatId = msg['chatId'];
        final chat = privateChats[chatId];
        if (chat != null) {
          chat.messages.add(ChatMessage.fromJson(msg['message']));
        }
        break;
      case 'private_chat_ended':
        privateChats.remove(msg['chatId']);
        chatMembership.remove(msg['chatId']); // NEW
        break;
      case 'all_private_chats_ended':
        privateChats.clear();
        chatMembership.clear(); // NEW
        break;
      case 'private_chat_membership_update': // NEW: receive public membership
        chatMembership[msg['chatId'] as String] =
            List<String>.from(msg['participants'] as List);
        break;
      case 'script_images_updated':
        scriptImageUrls = List<String>.from(msg['urls']);
        break;
      case 'script_characters_update':
        _room ??= RoomState();
        _room!.scriptCharacters = (msg['characters'] as List)
            .map((c) => ScriptCharacter.fromJson(c as Map<String, dynamic>))
            .toList();
        break;
      case 'character_assigned':
        myCharacterId = msg['characterId'] as String?;
        final bundledAlignment = msg['alignment'] as String?;
        if (bundledAlignment != null) myAlignment = bundledAlignment;
        final charDataJson = msg['characterData'] as Map<String, dynamic>?;
        if (charDataJson != null) {
          registerKnownCharacter(ScriptCharacter.fromJson(charDataJson));
        }
        if (myCharacterId != null && myCharacterId!.isNotEmpty) {
          _queuePopup(GamePopup.character());
        }
        break;
      case MessageType.setPlayerAlignment:
        myAlignment = msg['alignment'] as String?;
        if (myCharacterId != null && myCharacterId!.isNotEmpty) {
          _queuePopup(GamePopup.character());
        }
        break;
      case 'stop_countdown_alarm':
        SoundService.instance.stopAlarm();
        break;
      case 'mute_player':
      case 'unmute_player':
        _updatePlayerMuted(msg['playerId'] as String, msg['muted'] as bool);
        break;
      case MessageType.setPlayerAlive:
        _updatePlayerAliveStatus(
          msg['playerId'] as String,
          msg['alive'] as bool,
          msg['ghostVoteUsed'] as bool? ?? false,
        );
        break;
      case MessageType.setGhostVoteUsed:
        _updateGhostVoteUsed(
            msg['playerId'] as String, msg['ghostVoteUsed'] as bool);
        break;
      case 'reconnect_success':
        _myPlayerId = msg['playerId'];
        _reconnectRetries = 0;
        _showDisconnectedBanner = false;
        _reconnectLoopTimer?.cancel();
        _reconnectLoopTimer = null;
        break;
      case 'private_chats_sync':
        // Rebuild private chats from server data
        final chats = msg['chats'] as Map<String, dynamic>;
        privateChats.clear();
        chatMembership.clear(); // NEW: start fresh, then fill from sync
        chats.forEach((chatId, participantList) {
          final participants = List<String>.from(participantList);
          privateChats[chatId] = PrivateChat(
            sessionId: chatId,
            participants: participants,
            messages: [], // no history sent; will be populated as messages arrive
          );
          chatMembership[chatId] = participants; // NEW
        });
        // NEW: a reconnecting player can be part of at most one private
        // chat at a time (HostServer._isPlayerInAnyPrivateChat enforces
        // this), and this sync only ever contains chats THEY'RE in. If
        // one came back, drop them straight back into it instead of
        // stranding them on the main chat screen looking like they left.
        if (privateChats.isNotEmpty) {
          pendingPrivateChatId = privateChats.keys.first;
        }
        break;
      case MessageType.neighborDmMessage:
        final peerId = msg['peerId'] as String;
        final message = ChatMessage.fromJson(msg['message']);
        neighborDmMessages.putIfAbsent(peerId, () => []).add(message);
        if (message.senderId != _myPlayerId &&
            _openNeighborDmPeerId != peerId) {
          unreadNeighborDmPeerIds.add(peerId);
          pushBanner(BannerNotice(
            kind: BannerKind.neighborMsg,
            title: message.senderName,
            subtitle: message.text,
          ));
        }
        break;
      case 'neighbor_dm_sync':
        final threads = msg['threads'] as Map<String, dynamic>;
        neighborDmMessages.clear();
        threads.forEach((peerId, list) {
          neighborDmMessages[peerId] = (list as List)
              .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
              .toList();
        });
        break;
      case 'reconnect_failed':
        // FIX: this used to immediately give up and register as a brand
        // new player. But the most common reason reconnect fails is
        // timing, not a genuinely invalid identity — the host's
        // heartbeat check takes up to ~12s to notice the earlier
        // disconnect, and until it does, it correctly rejects a
        // reconnect from someone it still thinks is connected. A quick
        // app relaunch will almost always land in that window. Retry a
        // few times before concluding the saved identity is actually
        // gone, so a fast reconnect reliably lands back in the same seat
        // instead of silently forking into a second, duplicate player.
        if (_reconnectRetries < _maxReconnectRetries) {
          _reconnectRetries++;
          Future.delayed(const Duration(seconds: 3), () {
            if (_client != null && _persistentPlayerId != null) {
              _client!.send({
                'type': MessageType.reconnect,
                'playerId': _persistentPlayerId,
              });
            }
          });
        } else {
          final name = _myName ?? 'Player';
          _client?.send({'type': 'join_request', 'name': name});
        }
        break;
      case MessageType.gameWinner:
        final winAlignment = msg['alignment'] as String?;
        if (winAlignment != null) {
          winnerAlignment = winAlignment;
          _queuePopup(GamePopup.winner(winAlignment));
        }
        break;
      case 'error':
        lastError = msg['message'] as String?;
        pendingOutgoingRequestId = null;
        break;
      case 'countdown_start':
        countdownEndTime = DateTime.parse(msg['endsAt'] as String).toLocal();
        break;
      case 'countdown_cancel':
        countdownEndTime = null;
        break;
      case MessageType.nightModeChange:
        isNight = msg['isNight'] == true;
        dayNumber = msg['dayNumber'] as int? ?? dayNumber;
        _room?.isNight = isNight;
        _room?.dayNumber = dayNumber;
        break;
      case MessageType.gameReveal:
        _room ??= RoomState();
        revealGeneration++;
        _room!.revealOrder =
            List<String>.from(msg['order'] as List? ?? const []);
        _room!.revealedCardIds = {};
        _room!.revealedCharacterIds = {};
        _room!.revealedAlignments = {};
        break;
      case MessageType.revealCardOpened:
        final pid = msg['playerId'] as String;
        _room?.revealedCardIds.add(pid);
        _room?.revealedCharacterIds[pid] = msg['characterId'] as String? ?? '';
        _room?.revealedAlignments[pid] = msg['alignment'] as String? ?? 'good';
        final revealCharData = msg['characterData'] as Map<String, dynamic>?;
        if (revealCharData != null) {
          registerKnownCharacter(ScriptCharacter.fromJson(revealCharData));
        }
        break;
      default:
        break;
    }
    notifyListeners();
  }

  void _updateSeatingFromMsg(Map<String, dynamic> msg) {
    _room ??= RoomState();
    _room!.seating = List<String>.from(msg['seating']);
    final playersMap = msg['players'] as Map<String, dynamic>;
    _room!.players.clear();
    playersMap.forEach((key, value) {
      _room!.players[key] = Player.fromJson(value);
    });
    if (_myPlayerId != null && _room!.players.containsKey(_myPlayerId)) {
      _myPlayer = _room!.players[_myPlayerId];
    }
  }

  void _updatePlayerMuted(String playerId, bool muted) {
    _room?.players[playerId]?.muted = muted;
    if (playerId == _myPlayerId && _myPlayer != null) {
      _myPlayer!.muted = muted;
    }
  }

  void _updatePlayerAliveStatus(
      String playerId, bool alive, bool ghostVoteUsed) {
    _room?.players[playerId]?.alive = alive;
    _room?.players[playerId]?.ghostVoteUsed = ghostVoteUsed;
    if (playerId == _myPlayerId && _myPlayer != null) {
      _myPlayer!.alive = alive;
      _myPlayer!.ghostVoteUsed = ghostVoteUsed;
    }
  }

  void _updateGhostVoteUsed(String playerId, bool used) {
    _room?.players[playerId]?.ghostVoteUsed = used;
    if (playerId == _myPlayerId && _myPlayer != null) {
      _myPlayer!.ghostVoteUsed = used;
    }
  }

  void _addPrivateChat(String chatId, List<String> participants) {
    privateChats[chatId] =
        PrivateChat(sessionId: chatId, participants: participants);
  }

  void _updateParticipants(String chatId, List<String> participants) {
    privateChats[chatId]?.participants = participants;
  }

  void sendMainMessage(String text, {ChatMessage? replyTo}) => _client?.send({
        'type': 'chat_message',
        'text': text,
        if (replyTo != null) ...{
          'replyToId': replyTo.id,
          'replyToSenderName': replyTo.senderName,
          'replyToText': replyTo.text,
        },
      });

  void sendMainVoiceMessage(String base64Audio,
          {int? durationMs, ChatMessage? replyTo, String? voiceMime}) =>
      _client?.send({
        'type': MessageType.chatMessage,
        'text': '[Voice message]',
        'voiceBase64': base64Audio,
        if (durationMs != null) 'voiceDurationMs': durationMs,
        if (voiceMime != null) 'voiceMime': voiceMime,
        if (replyTo != null) ...{
          'replyToId': replyTo.id,
          'replyToSenderName': replyTo.senderName,
          'replyToText': replyTo.text,
        },
      });

  void adminSendMainVoiceMessage(String base64Audio,
      {int? durationMs, ChatMessage? replyTo, String? voiceMime}) {
    _hostServer?.adminSendMainVoice(base64Audio,
        durationMs: durationMs, replyTo: replyTo, voiceMime: voiceMime);
  }

  void sendDmMessage(String text,
          {ChatMessage? replyTo,
          String? voiceBase64,
          int? durationMs,
          String? voiceMime}) =>
      _client?.send({
        'type': 'dm_message',
        'text': text,
        if (replyTo != null) ...{
          'replyToId': replyTo.id,
          'replyToSenderName': replyTo.senderName,
          'replyToText': replyTo.text,
        },
        if (voiceBase64 != null) 'voiceBase64': voiceBase64,
        if (durationMs != null) 'voiceDurationMs': durationMs,
        if (voiceMime != null) 'voiceMime': voiceMime,
      });

  void requestPrivateChat(String targetId) {
    if (hasAnyPendingRequest || isInAnyPrivateChat) return;
    pendingOutgoingRequestId = targetId;
    _client?.send({'type': 'private_chat_request', 'targetId': targetId});
    notifyListeners();
  }

  void acceptPrivateChatRequest(String requesterId) {
    _client?.send(
        {'type': 'private_chat_request_accept', 'requesterId': requesterId});
    incomingRequestFromId = null;
    incomingRequestFromName = null;
    notifyListeners();
  }

  void declinePrivateChatRequest(String requesterId) {
    _client?.send(
        {'type': 'private_chat_request_decline', 'requesterId': requesterId});
    incomingRequestFromId = null;
    incomingRequestFromName = null;
    notifyListeners();
  }

  void requestJoinChat(String chatId) {
    if (hasAnyPendingRequest || isInAnyPrivateChat) return;
    pendingOutgoingRequestId = chatId;
    _client?.send({'type': 'join_chat_request', 'chatId': chatId});
    notifyListeners();
  }

  void acceptJoinChat(String chatId, String requesterId) {
    _client?.send({
      'type': 'join_chat_accept',
      'chatId': chatId,
      'requesterId': requesterId
    });
    incomingJoinChatId = null;
    incomingJoinRequesterId = null;
    incomingJoinRequesterName = null;
    notifyListeners();
  }

  void declineJoinChat(String chatId, String requesterId) {
    _client?.send({
      'type': 'join_chat_decline',
      'chatId': chatId,
      'requesterId': requesterId
    });
    incomingJoinChatId = null;
    incomingJoinRequesterId = null;
    incomingJoinRequesterName = null;
    notifyListeners();
  }

  void sendPrivateMessage(String chatId, String text,
          {ChatMessage? replyTo,
          String? voiceBase64,
          int? durationMs,
          String? voiceMime}) =>
      _client?.send({
        'type': 'private_message',
        'chatId': chatId,
        'text': text,
        if (replyTo != null) ...{
          'replyToId': replyTo.id,
          'replyToSenderName': replyTo.senderName,
          'replyToText': replyTo.text,
        },
        if (voiceBase64 != null) 'voiceBase64': voiceBase64,
        if (durationMs != null) 'voiceDurationMs': durationMs,
        if (voiceMime != null) 'voiceMime': voiceMime,
      });

  void leavePrivateChat(String chatId) {
    _client?.send({'type': 'leave_private_chat', 'chatId': chatId});
    // FIX: the server only notifies the OTHER remaining participants
    // (via participant_left) — the leaver never receives anything
    // about their own departure. Without clearing this locally, this
    // device's own privateChats map keeps a stale entry forever,
    // which is exactly what made isInAnyPrivateChat stay true and
    // silently blocked this player from starting or joining ANY new
    // private chat after leaving one.
    privateChats.remove(chatId);
    if (pendingPrivateChatId == chatId) pendingPrivateChatId = null;
    // NEW: optimistic update of public membership map
    final existing = chatMembership[chatId];
    if (existing != null && _myPlayerId != null) {
      final updated = existing.where((id) => id != _myPlayerId).toList();
      if (updated.isEmpty) {
        chatMembership.remove(chatId);
      } else {
        chatMembership[chatId] = updated;
      }
    }
    notifyListeners();
  }

  Future<void> _loadPersistentId() async {
    final prefs = await SharedPreferences.getInstance();
    _persistentPlayerId = prefs.getString('playerId');
    _myName = prefs.getString('playerName');
    // NEW: host IP/port weren't being persisted at all before, so even
    // with a saved player ID, a cold app start had no idea WHERE to
    // reconnect to — Resume Game (see below) depends on these.
    _hostIp = prefs.getString('lastHostIp') ?? '';
    _hostPort = prefs.getInt('lastHostPort') ?? 0;
    notifyListeners();
  }

  Future<void> _savePersistentId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerId', id);
    if (_hostIp.isNotEmpty && _hostPort != 0) {
      await prefs.setString('lastHostIp', _hostIp);
      await prefs.setInt('lastHostPort', _hostPort);
    }
    _persistentPlayerId = id;
  }

  // NEW: wipes the saved session entirely — used when the host explicitly
  // tells us this identity is no longer valid (see join_declined below),
  // so a dead session doesn't keep offering "Resume Game" forever.
  Future<void> _clearPersistentSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('playerId');
    await prefs.remove('lastHostIp');
    await prefs.remove('lastHostPort');
    _persistentPlayerId = null;
    notifyListeners();
  }

  Future<void> _savePlayerName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('playerName', name);
    _myName = name;
  }

  // NEW: whether there's a previous session this device could try to
  // resume — used by the home screen to decide whether to show a
  // "Resume Game" option instead of making the person re-enter
  // everything through Join Game.
  bool get hasResumableSession =>
      _persistentPlayerId != null &&
      _myName != null &&
      _hostIp.isNotEmpty &&
      _hostPort != 0 &&
      !isClientConnected;

  /// Attempts to resume the most recent session on this device, using the
  /// same reconnect-with-retry path as a normal Join Game — see joinGame()
  /// and the reconnect_failed handling above. Returns true once the
  /// attempt is under way (not once it's actually confirmed successful;
  /// same contract as joinGame()).
  Future<bool> resumeSession() async {
    if (!hasResumableSession) return false;
    return joinGame(_hostIp, _hostPort, _myName!);
  }

  List<ScriptCharacter> get activeFabled => _room?.activeFabled ?? const [];

  /// Host only: sets which Fabled are in play and tells everyone.
  void setActiveFabled(List<ScriptCharacter> chars) {
    for (final c in chars) {
      registerKnownCharacter(c);
    }
    _hostServer?.setActiveFabled(chars);
    notifyListeners();
  }
}
