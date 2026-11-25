/// A single character as it appears in an imported script — either an
/// official character (resolved against the bundled reference database) or
/// a homebrew character (fully defined inside the script file itself).
///
/// This is deliberately public/non-secret data: everyone at the table
/// already knows which characters are "in play" in a real game, they just
/// don't know who has which one. What's private is the *assignment* of a
/// character to a specific player — that lives separately in
/// RoomState.assignedCharacters (host-server.dart) and is never broadcast
/// to everyone the way this character list is.
class ScriptCharacter {
  final String id;
  final String name;
  final String team; // townsfolk, outsider, minion, demon, traveler, fabled
  final String ability;
  final String? image;

  // NEW: night order. Public information at a real table — the storyteller
  // wakes characters in this order and everyone knows the order exists,
  // even if they don't know who's who. 0 means "doesn't wake that night".
  // These numbers come straight from roles.json (the same reference
  // database ScriptLibrary already resolves official characters against)
  // and are absolute positions across every official character, not just
  // the ones in this script — see NightOrderScreen for how they get turned
  // into a 1st/2nd/3rd... order for the actual imported script.
  final int firstNight;
  final String firstNightReminder;
  final int otherNight;
  final String otherNightReminder;
  // NEW: the reminder tokens a character places at the table (e.g. the
  // Poisoner's "Poisoned", the Witch's "Cursed") — straight from
  // roles.json's `reminders`/`remindersGlobal` arrays. Public/non-secret,
  // same as the rest of this class, broadcast the same way. Feeds the
  // quick-tag picker in the notes feature — see PlayerNote in player.dart
  // and allTags() below.
  final List<String> reminders;
  final List<String> remindersGlobal;
  final String flavor; // NEW — flavor text shown alongside the ability

  const ScriptCharacter({
    required this.id,
    required this.name,
    required this.team,
    required this.ability,
    this.image,
    this.firstNight = 0,
    this.firstNightReminder = '',
    this.otherNight = 0,
    this.otherNightReminder = '',
    this.reminders = const [],
    this.remindersGlobal = const [],
    this.flavor = '',
  });

  factory ScriptCharacter.fromJson(Map<String, dynamic> json) {
    return ScriptCharacter(
      id: json['id'] as String,
      name: (json['name'] as String?)?.trim().isNotEmpty == true
          ? json['name'] as String
          : json['id'] as String,
      team: _normalizeTeam(json['team'] as String?),
      ability: (json['ability'] as String?) ?? '',
      image: _firstImage(json['image']),
      firstNight: (json['firstNight'] as num?)?.toInt() ?? 0,
      firstNightReminder: (json['firstNightReminder'] as String?) ?? '',
      otherNight: (json['otherNight'] as num?)?.toInt() ?? 0,
      otherNightReminder: (json['otherNightReminder'] as String?) ?? '',
      reminders: _stringList(json['reminders']),
      remindersGlobal: _stringList(json['remindersGlobal']),
      flavor: (json['flavor'] as String?) ?? '',
    );
  }

  static String? _firstImage(dynamic image) {
    if (image is String) return image;
    if (image is List && image.isNotEmpty) return image.first as String;
    return null;
  }

  static List<String> _stringList(dynamic value) {
    if (value is List) return value.map((e) => e.toString()).toList();
    return const [];
  }

  // NEW: roles.json spells this team the official British way,
  // "traveller" — everywhere else in this app (teamOrder, teamColor, the
  // non-traveler headcount in BotcSetup/TeamDistributionRow, etc.)
  // standardizes on the single-L "traveler". Without this, every
  // traveler in roles.json silently failed the
  // `official.team == 'traveler'` check in ScriptLibrary.mergeScript, so
  // none of them were ever auto-appended to an imported script — this is
  // the actual root cause. Normalizing right here at the JSON boundary
  // means every downstream call site can keep assuming the one spelling
  // it already assumes.
  static String _normalizeTeam(String? raw) {
    final team = raw ?? 'townsfolk';
    if (team == 'traveller') return 'traveler';
    return team;
  }

  /// Returns a copy of this character with any field it left blank/zero
  /// filled in from [official]. Used when a script re-declares an official
  /// character as a full object — e.g. to translate its name and ability
  /// text — but doesn't repeat night-order data that's already sitting in
  /// the bundled reference database under the same id. Whatever the
  /// script DID specify (translated name, ability, etc.) is kept as-is.
  ScriptCharacter mergeMissingFrom(ScriptCharacter official) {
    return ScriptCharacter(
      id: id,
      name: name,
      team: team,
      ability: ability.trim().isNotEmpty ? ability : official.ability,
      image: image ?? official.image,
      firstNight: firstNight != 0 ? firstNight : official.firstNight,
      firstNightReminder: firstNightReminder.isNotEmpty
          ? firstNightReminder
          : official.firstNightReminder,
      otherNight: otherNight != 0 ? otherNight : official.otherNight,
      otherNightReminder: otherNightReminder.isNotEmpty
          ? otherNightReminder
          : official.otherNightReminder,
      reminders: reminders.isNotEmpty ? reminders : official.reminders,
      remindersGlobal: remindersGlobal.isNotEmpty
          ? remindersGlobal
          : official.remindersGlobal,
      flavor: flavor.trim().isNotEmpty ? flavor : official.flavor,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'team': team,
        'ability': ability,
        if (image != null) 'image': image,
        'firstNight': firstNight,
        'firstNightReminder': firstNightReminder,
        'otherNight': otherNight,
        'otherNightReminder': otherNightReminder,
        'reminders': reminders,
        'remindersGlobal': remindersGlobal,
        'flavor': flavor,
      };

  /// Canonical BOTC team order, used to group the character picker and the
  /// night-order-ish "who's what" displays.
  static const teamOrder = [
    'townsfolk',
    'outsider',
    'minion',
    'demon',
    'traveler',
    'fabled',
  ];

  static String teamLabel(String team) {
    switch (team) {
      case 'townsfolk':
        return 'Townsfolk';
      case 'outsider':
        return 'Outsider';
      case 'minion':
        return 'Minion';
      case 'demon':
        return 'Demon';
      case 'traveler':
        return 'Traveler';
      case 'fabled':
        return 'Fabled';
      case 'custom':
        return 'Custom';
      default:
        return team;
    }
  }

  /// Every distinct reminder tag across [characters], each paired with
  /// one character to color it by (the first one it's found on — a tag
  /// like "Poisoned" often appears on several characters; any single
  /// match is fine purely as a color hint). Used by the notes feature's
  /// quick-tag picker.
  static List<MapEntry<String, ScriptCharacter>> allTags(
      List<ScriptCharacter> characters) {
    final seen = <String, ScriptCharacter>{};
    for (final c in characters) {
      for (final r in [...c.reminders, ...c.remindersGlobal]) {
        final trimmed = r.trim();
        if (trimmed.isEmpty) continue;
        seen.putIfAbsent(trimmed, () => c);
      }
    }
    final entries = seen.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }
}
