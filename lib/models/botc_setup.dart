/// Standard Blood on the Clocktower character distribution — how many
/// Townsfolk / Outsiders / Minions / a Demon should be in play, based on
/// the number of players. This is the same table printed on the game's
/// physical setup sheet.
///
/// Travellers sit outside this table entirely: adding a Traveller does
/// not grow these numbers. Callers must pass the NON-Traveller player
/// count, not the raw seated count — see TeamDistributionRow, which does
/// that subtraction.
class BotcSetup {
  BotcSetup._();

  // Index 0 = 5 players, index 10 = 15 players. Each row is
  // [townsfolk, outsider, minion, demon] and always sums to the player
  // count for that row — that's not a coincidence, it's how the game
  // guarantees exactly one character token per player.
  static const List<List<int>> _table = [
    [3, 0, 1, 1], // 5
    [3, 1, 1, 1], // 6
    [5, 0, 1, 1], // 7
    [5, 1, 1, 1], // 8
    [5, 2, 1, 1], // 9
    [7, 0, 2, 1], // 10
    [7, 1, 2, 1], // 11
    [7, 2, 2, 1], // 12
    [9, 0, 3, 1], // 13
    [9, 1, 3, 1], // 14
    [9, 2, 3, 1], // 15
  ];

  /// Returns [townsfolk, outsider, minion, demon] for [nonTravelerCount].
  /// Counts below 5 or above 15 are clamped to the nearest defined row —
  /// the real game doesn't define numbers outside 5-15 players: below 5
  /// there aren't enough players to start, and above 15 the rules say
  /// extra players should become Travellers rather than growing these
  /// counts further.
  static List<int> countsFor(int nonTravelerCount) {
    final clamped = nonTravelerCount.clamp(5, 15);
    return _table[clamped - 5];
  }
}
