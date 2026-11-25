import 'package:flutter/material.dart';
import '../models/room_state.dart';
import '../models/script_character.dart';
import '../models/botc_setup.dart';
import 'character_picker_dialog.dart' show teamColor;

/// Small colored-number readout of the standard BOTC character
/// distribution (Townsfolk / Outsider / Minion / Demon) for the current
/// game, based on player count. This is public, standard-rules
/// information — not a secret — so it's shown to the storyteller and
/// every player alike.
///
/// Travellers are deliberately excluded from the count this is based on:
/// per the rules, a Traveller joining mid-game does NOT change how many
/// Townsfolk/Outsiders/Minions/Demons should be in play. A seated player
/// only gets excluded from the count once they've actually been assigned
/// a Traveller character — an empty/unassigned seat still counts, since
/// most players are not Travellers by default.
class TeamDistributionRow extends StatelessWidget {
  final RoomState room;
  const TeamDistributionRow({super.key, required this.room});

  ScriptCharacter? _characterById(String id) {
    for (final c in room.scriptCharacters) {
      if (c.id == id) return c;
    }
    return null;
  }

  int get _nonTravelerCount {
    var count = 0;
    for (final playerId in room.seating) {
      final charId = room.assignedCharacters[playerId];
      final character = charId == null ? null : _characterById(charId);
      if (character?.team == 'traveler') continue;
      count++;
    }
    return count;
  }

  @override
  Widget build(BuildContext context) {
    final total = room.seating.length;
    if (total == 0) return const SizedBox.shrink();

    final nonTraveler = _nonTravelerCount;
    final counts = BotcSetup.countsFor(nonTraveler);
    const labels = ['T', 'O', 'M', 'D'];
    const teams = ['townsfolk', 'outsider', 'minion', 'demon'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Standard Setup',
            style: TextStyle(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(room.isNight ? Icons.nightlight_round : Icons.wb_sunny_outlined,
                  size: 15, color: room.isNight ? Colors.indigo : Colors.orange),
              const SizedBox(width: 6),
              Text('${room.isNight ? 'Night' : 'Day'} ${room.dayNumber}',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: List.generate(4, (i) {
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: teamColor(teams[i]),
                      child: Text(
                        '${counts[i]}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(labels[i], style: const TextStyle(fontSize: 11)),
                  ],
                ),
              );
            }),
          ),
          if (nonTraveler < 5)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Need at least 5 non-Traveller players',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            )
          else if (nonTraveler > 15)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Players beyond 15 should be Travellers',
                style: TextStyle(fontSize: 10, color: Colors.grey),
              ),
            ),
        ],
      ),
    );
  }
}
