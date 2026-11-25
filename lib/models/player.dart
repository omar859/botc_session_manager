enum PlayerStatus { connected, disconnected }

// NEW: a note about a player — freeform text plus quick-select "tags"
// sourced from the currently-imported script's reminder tokens (e.g. the
// Poisoner's "Poisoned", a generic "Dead" — see
// ScriptCharacter.reminders/remindersGlobal, straight out of roles.json).
// Tags are plain strings rather than character references so a note
// stays readable even if the script is later re-imported under different
// ids — a stale tag just renders in a neutral color instead of vanishing
// (see NoteTagRow in player_note_dialog.dart).
class PlayerNote {
  final String text;
  final List<String> tags;

  const PlayerNote({this.text = '', this.tags = const []});

  static const empty = PlayerNote();

  bool get isEmpty => text.trim().isEmpty && tags.isEmpty;

  Map<String, dynamic> toJson() => {'text': text, 'tags': tags};

  factory PlayerNote.fromJson(Map<String, dynamic> json) => PlayerNote(
        text: (json['text'] as String?) ?? '',
        tags: (json['tags'] as List?)?.map((e) => e.toString()).toList() ?? [],
      );

  // Accepts either the new {text, tags} shape or a bare String, so notes
  // saved before tags existed still load instead of throwing on decode.
  factory PlayerNote.fromDynamic(dynamic value) {
    if (value is String) return PlayerNote(text: value);
    if (value is Map<String, dynamic>) return PlayerNote.fromJson(value);
    return PlayerNote.empty;
  }
}

class Player {
  final String id;
  final String name;
  int seat;
  PlayerStatus status;
  bool muted;
  // NEW: BOTC status. Public knowledge at the table — broadcast to
  // everyone the same way seat/muted already are, not admin-only.
  // ghostVoteUsed only means anything while alive == false, but is kept
  // as its own field (rather than derived) so a revive can cleanly reset
  // it without losing the flag's meaning.
  bool alive;
  bool ghostVoteUsed;
  List<ChatMessage>
      dmThread; // Storyteller DM messages (host-side authoritative copy)
  PlayerNote adminNotes; // host only, never transmitted

  Player({
    required this.id,
    required this.name,
    this.seat = -1,
    this.status = PlayerStatus.connected,
    this.muted = false,
    this.alive = true,
    this.ghostVoteUsed = false,
    List<ChatMessage>? dmThread,
    this.adminNotes = PlayerNote.empty,
  }) : dmThread = dmThread ?? [];

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'seat': seat,
        'status': status.name,
        'muted': muted,
        'alive': alive,
        'ghostVoteUsed': ghostVoteUsed,
      };

  factory Player.fromJson(Map<String, dynamic> json) => Player(
        id: json['id'],
        name: json['name'],
        seat: json['seat'] ?? -1,
        status: PlayerStatus.values.firstWhere(
          (e) => e.name == json['status'],
          orElse: () => PlayerStatus.connected,
        ),
        muted: json['muted'] ?? false,
        alive: json['alive'] ?? true,
        ghostVoteUsed: json['ghostVoteUsed'] ?? false,
      );
}

class ChatMessage {
  final String id;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime timestamp;
  final String? channelId;
  // NEW: when non-null, this is a storyteller "bluff" message — a list of
  // character IDs the storyteller is claiming (as the demon) to be the
  // "not in play" characters. The chat renderer switches to a special
  // chip-based bubble (see BluffMessageBubble) instead of showing `text`.
  // Rides inside a normal chat_message payload, so no new wire type.
  final List<String>? bluffs;
  final String? replyToId;
  final String? replyToSenderName;
  final String? replyToText;
  final String? voiceBase64;
  final int? voiceDurationMs;
  final String? voiceMime;

  ChatMessage({
    String? id,
    required this.senderId,
    required this.senderName,
    required this.text,
    DateTime? timestamp,
    this.channelId,
    this.bluffs,
    this.replyToId,
    this.replyToSenderName,
    this.replyToText,
    this.voiceBase64,
    this.voiceDurationMs,
    this.voiceMime,
  })  : timestamp = timestamp ?? DateTime.now(),
        id = id ??
            '${senderId}_${timestamp?.microsecondsSinceEpoch ?? DateTime.now().microsecondsSinceEpoch}';

  Map<String, dynamic> toJson() => {
        'id': id,
        'senderId': senderId,
        'senderName': senderName,
        'text': text,
        'timestamp': timestamp.toIso8601String(),
        'channelId': channelId,
        if (bluffs != null) 'bluffs': bluffs,
        if (replyToId != null) 'replyToId': replyToId,
        if (replyToSenderName != null) 'replyToSenderName': replyToSenderName,
        if (replyToText != null) 'replyToText': replyToText,
        if (voiceBase64 != null) 'voiceBase64': voiceBase64,
        if (voiceDurationMs != null) 'voiceDurationMs': voiceDurationMs,
        if (voiceMime != null) 'voiceMime': voiceMime,
      };

  factory ChatMessage.fromJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String?,
        senderId: json['senderId'],
        senderName: json['senderName'],
        text: json['text'],
        timestamp: DateTime.parse(json['timestamp']),
        channelId: json['channelId'],
        bluffs: json['bluffs'] != null
            ? List<String>.from(json['bluffs'] as List<dynamic>)
            : null,
        replyToId: json['replyToId'] as String?,
        replyToSenderName: json['replyToSenderName'] as String?,
        replyToText: json['replyToText'] as String?,
        voiceBase64: json['voiceBase64'] as String?,
        voiceDurationMs: (json['voiceDurationMs'] as num?)?.toInt(),
        voiceMime: json['voiceMime'] as String?,
      );
}
