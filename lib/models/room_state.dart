import 'player.dart';
import 'private_chat.dart';
import 'script_character.dart';

enum ChatMode { open, locked }

class RoomState {
  String roomCode;
  Map<String, Player> players;
  final Map<String, Player> pendingRequests;
  List<String> seating; // ordered, circular
  Map<String, PrivateChat> privateChats;
  ChatMode chatMode;
  bool neighborRestriction;
  // NEW: current day/night phase. Public at the table — broadcast to
  // everyone (see HostServer.setNight) so every client can dim its screen
  // and play the night ambience / day alarm.
  bool isNight;
  int dayNumber;
  List<String> scriptImagePaths; // filenames served via /script/<file>

  // NEW: the imported script's character list. Public/non-secret — every
  // player is allowed to know what's "in play" in a real game, so this is
  // broadcast to everyone as-is.
  List<ScriptCharacter> scriptCharacters;

  // NEW: playerId -> characterId. This is the actual secret truth of who
  // has what. Deliberately kept OFF the Player object and out of
  // Player.toJson(), since Player objects get serialized into broadcast
  // messages (seating_update) that go to every client — this map must
  // never be broadcast wholesale, only sent to each player individually as
  // their own single entry (see HostServer.assignCharacters).
  Map<String, String> assignedCharacters;
  // NEW: full ScriptCharacter data for assignments that aren't part of
  // the current script — either an official character picked via the
  // "show all characters" toggle, or a freely-typed custom one. Keyed
  // by playerId (not characterId) so two different players can even
  // have two different customs with the same typed name. This is what
  // lets ability/flavor text survive a reconnect or an end-game reveal
  // for a character characterById can't otherwise resolve.
  Map<String, ScriptCharacter> extraCharacterData;
  // Fabled currently in play — full character objects (not just ids)
  // so devices can show them even if they aren't in the script.
  List<ScriptCharacter> activeFabled;
  // NEW: playerId -> 'good' | 'evil'. Same secrecy treatment as
  // assignedCharacters — deliberately off the Player object so it's
  // never swept into a seating_update broadcast. Defaults to 'good'
  // wherever it's missing (see HostServer/GameProvider alignmentFor).
  Map<String, String> playerAlignments;

  // NEW: once the end-game reveal broadcasts a card open, alignment
  // becomes public at the table (the game is over) — this mirrors
  // revealedCharacterIds exactly, just for alignment.
  Map<String, String> revealedAlignments;

  /// Every bluff delivery for each player, retained until that player leaves.
  Map<String, List<List<String>>> playerBluffs;

  // NEW: persistent direct-message threads between two PLAYERS who are
  // (or were) seating neighbors — keyed by neighborDmKey(a, b), a stable
  // unordered pair key so both sides look up the same list. Deliberately
  // separate from privateChats: those are ephemeral, request/accept, and
  // get wiped by chat lock / night falling / force-close. This is meant
  // to behave like the Storyteller DM instead — always available, no
  // consent step, untouched by any of that — just between two players
  // instead of a player and the storyteller.
  Map<String, List<ChatMessage>> neighborDmThreads;

  // NEW: end-of-game reveal state. revealOrder is deliberately JUST a
  // list of player IDs — no names, no characters — because it's exactly
  // what's safe to hand to every player's device the moment "Reveal
  // Characters" is pressed, before the storyteller has tapped anything.
  // revealedCardIds / revealedCharacterIds fill in one entry at a time,
  // only as each card actually gets tapped open (see
  // HostServer.revealCard). On the HOST's own device this is somewhat
  // redundant with assignedCharacters (which it already has in full) —
  // it's kept anyway so both host and client screens can read the exact
  // same fields the exact same way.
  List<String> revealOrder;
  Set<String> revealedCardIds;
  Map<String, String> revealedCharacterIds;

  RoomState({
    this.roomCode = '',
    Map<String, Player>? players,
    Map<String, Player>? pendingRequests,
    List<String>? seating,
    Map<String, PrivateChat>? privateChats,
    this.chatMode = ChatMode.open,
    this.neighborRestriction = false,
    this.isNight = false,
    this.dayNumber = 1,
    List<String>? scriptImagePaths,
    List<ScriptCharacter>? scriptCharacters,
    Map<String, String>? assignedCharacters,
    Map<String, ScriptCharacter>? extraCharacterData,
    List<ScriptCharacter>? activeFabled,
    Map<String, String>? playerAlignments,
    Map<String, String>? revealedAlignments,
    Map<String, List<List<String>>>? playerBluffs,
    List<String>? revealOrder,
    Set<String>? revealedCardIds,
    Map<String, String>? revealedCharacterIds,
    Map<String, List<ChatMessage>>? neighborDmThreads,
  })  : players = players ?? {},
        pendingRequests = pendingRequests ?? <String, Player>{},
        seating = seating ?? <String>[],
        privateChats = privateChats ?? <String, PrivateChat>{},
        scriptImagePaths = scriptImagePaths ?? <String>[],
        scriptCharacters = scriptCharacters ?? <ScriptCharacter>[],
        assignedCharacters = assignedCharacters ?? <String, String>{},
        extraCharacterData = extraCharacterData ?? <String, ScriptCharacter>{},
        activeFabled = activeFabled ?? <ScriptCharacter>[],
        playerAlignments = playerAlignments ?? <String, String>{},
        revealedAlignments = revealedAlignments ?? <String, String>{},
        playerBluffs = playerBluffs ?? <String, List<List<String>>>{},
        revealOrder = revealOrder ?? <String>[],
        revealedCardIds = revealedCardIds ?? <String>{},
        revealedCharacterIds = revealedCharacterIds ?? <String, String>{},
        neighborDmThreads = neighborDmThreads ?? <String, List<ChatMessage>>{};

  List<String> getNeighbors(String playerId) {
    final idx = seating.indexOf(playerId);
    if (idx == -1 || seating.length < 2) return [];
    final left = seating[(idx - 1) % seating.length];
    final right = seating[(idx + 1) % seating.length];
    return [left, right];
  }

  bool areNeighbors(String player1, String player2) =>
      getNeighbors(player1).contains(player2);

  /// Stable unordered key for a neighbor-DM thread between two players.
  /// The key is independent of ordering so both sides use the same map
  /// entry: `neighborDmKey(a,b) == neighborDmKey(b,a)`.
  static String neighborDmKey(String a, String b) {
    // NEW: stable, order-independent key for a neighbor-DM thread between
    // two players, so a's lookup and b's lookup hit the same list
    // regardless of who's asking.
    return a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';
  }

  /// Returns the thread for the unordered pair (a,b). Creates it if
  /// necessary and returns a reference to the mutable list.
  List<ChatMessage> getNeighborDmThread(String a, String b) {
    final k = neighborDmKey(a, b);
    return neighborDmThreads.putIfAbsent(k, () => <ChatMessage>[]);
  }

  /// Append a message to the neighbor-DM between a and b.
  void addNeighborDmMessage(String a, String b, ChatMessage msg) {
    final thread = getNeighborDmThread(a, b);
    thread.add(msg);
  }
}
