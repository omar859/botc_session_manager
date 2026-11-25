import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/script_character.dart';

/// Loads assets/data/roles.json (the bundled reference database of every
/// official character) once, and merges it against whatever a given script
/// file contains.
///
/// A script entry is one of:
///  - the string "_meta" object — skipped (script title/author/night order)
///  - a bare string like "empath" — an official character; resolved against
///    the bundled reference database
///  - a full object — a homebrew character; already self-contained, used
///    as-is
///
/// This only ever needs to run on the device that imports the script (the
/// host) — the fully-resolved character list it produces gets broadcast to
/// everyone else, so clients never need their own copy of roles.json.
class ScriptLibrary {
  ScriptLibrary._();
  static final ScriptLibrary instance = ScriptLibrary._();

  Map<String, ScriptCharacter>? _officialById;

  // Case/whitespace-insensitive matching — a script export and roles.json
  // agreeing on an ID's letters but not its exact casing (or a stray
  // space) previously caused a silent, hard-to-notice mismatch.
  String _normalize(String id) => id.trim().toLowerCase();

  Future<void> _ensureLoaded() async {
    if (_officialById != null) return;
    try {
      final raw = await rootBundle.loadString('assets/data/roles.json');
      final decoded = jsonDecode(raw) as List<dynamic>;
      _officialById = {
        for (final entry in decoded)
          if (entry is Map<String, dynamic> && entry['id'] != null)
            _normalize(entry['id'] as String): ScriptCharacter.fromJson(entry),
      };
    } catch (e) {
      // Missing/malformed asset — degrade gracefully instead of crashing
      // the import. Official characters will show up as bare IDs until the
      // asset is added; see the docx/README note on where to source it.
      _officialById = {};
    }
  }

  /// Parses a raw script JSON (the decoded top-level list from a .json
  /// file exported by the script tool) into a fully-resolved character
  /// list, skipping the _meta entry.
  ///
  /// NEW: every official Traveller from roles.json is appended at the end,
  /// regardless of whether this particular script's author included them.
  /// In real play a storyteller can bring in any Traveller at any point
  /// (most commonly to seat a latecomer) — that shouldn't depend on the
  /// imported script happening to list one. Travellers already declared by
  /// the script (official or homebrew) are left exactly as the script
  /// defined them; this only adds the official ones that are otherwise
  /// missing, so nothing already-resolved gets overwritten.
  Future<List<ScriptCharacter>> mergeScript(List<dynamic> rawScript) async {
    await _ensureLoaded();
    final result = <ScriptCharacter>[];
    final includedIds = <String>{};

    for (final entry in rawScript) {
      if (entry is String) {
        if (entry == '_meta') continue;
        final normalized = _normalize(entry);
        final official = _officialById![normalized];
        final character = official ??
            ScriptCharacter(
              id: entry,
              name: entry,
              team: 'townsfolk',
              ability:
                  '(Unrecognized character ID — add roles.json to assets/data/ '
                  'so official characters resolve automatically.)',
            );
        result.add(character);
        includedIds.add(_normalize(character.id));
      } else if (entry is Map<String, dynamic>) {
        if (entry['id'] == '_meta') continue;
        final parsed = ScriptCharacter.fromJson(entry);
        // A full object reusing an official ID — most often a translated
        // or otherwise customized copy of an official character. Fill in
        // anything it left blank (night order, in particular) from the
        // official reference data, rather than trusting the object alone.
        final official = _officialById![_normalize(parsed.id)];
        final merged =
            official == null ? parsed : parsed.mergeMissingFrom(official);
        result.add(merged);
        includedIds.add(_normalize(merged.id));
      }
    }

    // Always make every official Traveller available for assignment, even
    // if this script didn't list it.
    for (final official in _officialById!.values) {
      if (official.team == 'traveler' &&
          !includedIds.contains(_normalize(official.id))) {
        result.add(official);
        includedIds.add(_normalize(official.id));
      }
    }

    return result;
  }

  /// Every official character from roles.json, for display purposes
  /// (the Game Info screen) — independent of any live session, since
  /// this needs to work from the home screen before hosting/joining.
  Future<List<ScriptCharacter>> loadAllOfficialCharacters() async {
    await _ensureLoaded();
    final list = _officialById!.values.toList();
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
  }
}
