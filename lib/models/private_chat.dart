import 'player.dart';

class PrivateChat {
  final String sessionId;
  List<String> participants; // dynamic group, grows via join requests
  List<ChatMessage> messages;
  DateTime startedAt;

  PrivateChat({
    required this.sessionId,
    required this.participants,
    List<ChatMessage>? messages,
    DateTime? startedAt,
  })  : messages = messages ?? [],
        startedAt = startedAt ?? DateTime.now();

  int get playerCount => participants.length;

  bool containsPlayer(String playerId) => participants.contains(playerId);

  void addParticipant(String playerId) {
    if (!participants.contains(playerId)) participants.add(playerId);
  }

  void removeParticipant(String playerId) {
    participants.remove(playerId);
  }

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'participants': participants,
        'messageCount': messages.length,
      };
}
