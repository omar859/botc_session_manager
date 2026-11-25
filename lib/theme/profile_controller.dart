import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ProfileGameRecord {
  final DateTime playedAt;
  final String role;
  final String alignment;
  final String outcome;
  final String gameId;

  const ProfileGameRecord({
    required this.playedAt,
    required this.role,
    required this.alignment,
    required this.outcome,
    required this.gameId,
  });

  bool get isWin => outcome == 'win';
  bool get isLoss => outcome == 'loss';

  Map<String, dynamic> toJson() => {
        'playedAt': playedAt.toIso8601String(),
        'role': role,
        'alignment': alignment,
        'outcome': outcome,
        'gameId': gameId,
      };

  factory ProfileGameRecord.fromJson(Map<String, dynamic> json) {
    return ProfileGameRecord(
      playedAt: DateTime.tryParse(json['playedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      role: json['role'] as String? ?? 'Unknown',
      alignment: json['alignment'] as String? ?? 'unknown',
      outcome: json['outcome'] as String? ?? 'loss',
      gameId: json['gameId'] as String? ?? '',
    );
  }
}

class ProfileController extends ChangeNotifier {
  static const _nameKey = 'profile.name';
  static const _historyKey = 'profile.history';

  String name = '';
  List<ProfileGameRecord> history = [];
  final Set<String> _recordedGameIds = {};

  int get gamesPlayed => history.length;
  int get wins => history.where((game) => game.isWin).length;
  int get losses => history.where((game) => game.isLoss).length;

  String? get mostPlayedRole {
    if (history.isEmpty) return null;
    final counts = <String, int>{};
    for (final game in history) {
      if (game.role == 'Storyteller') continue;
      counts[game.role] = (counts[game.role] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    return counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    name = prefs.getString(_nameKey) ?? prefs.getString('playerName') ?? '';
    final raw = prefs.getString(_historyKey);
    if (raw != null) {
      try {
        history = (jsonDecode(raw) as List)
            .whereType<Map<String, dynamic>>()
            .map(ProfileGameRecord.fromJson)
            .toList();
      } catch (_) {
        history = [];
      }
    }
    notifyListeners();
  }

  Future<void> setName(String value) async {
    final cleaned = value.trim();
    if (name == cleaned) return;
    name = cleaned;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, cleaned);
    await prefs.setString('playerName', cleaned);
  }

  Future<void> recordGame({
    required String gameId,
    required String role,
    required String alignment,
    required String outcome,
  }) async {
    if (gameId.isEmpty || _recordedGameIds.contains(gameId)) return;
    _recordedGameIds.add(gameId);
    history = [
      ProfileGameRecord(
        playedAt: DateTime.now(),
        role: role,
        alignment: alignment,
        outcome: outcome,
        gameId: gameId,
      ),
      ...history,
    ];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _historyKey,
      jsonEncode(history.map((game) => game.toJson()).toList()),
    );
  }
}
