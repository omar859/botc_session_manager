import 'package:flutter/services.dart' show rootBundle, AssetManifest;
import '../models/script_character.dart';

/// Resolves a bundled icon for a script character by scanning every
/// bundled asset for a file whose name starts with "icon_" (case
/// insensitive), regardless of which folder it lives in — so this
/// works whether the folder is named assets/icons/ or assets/icon/.
/// Falls back to one of the six per-team defaults —
/// icon_townsfolk.png, icon_outsider.png, icon_minion.png,
/// icon_demon.png, icon_traveler.png, icon_fabled.png — when no
/// character-specific icon exists.
class CharacterIcons {
  CharacterIcons._();
  static final CharacterIcons instance = CharacterIcons._();

  Map<String, String>? _byKey; // normalized key -> full asset path
  Future<void>? _loading;

  String _normalize(String raw) =>
      raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> ensureLoaded() {
    if (_byKey != null) return Future.value();
    return _loading ??= _load();
  }

  /// Forces a fresh scan — call this right after a new script import,
  /// in case the app was already running when icons were added.
  void invalidate() {
    _byKey = null;
    _loading = null;
  }

  Future<void> _load() async {
    final map = <String, String>{};
    List<String> allAssetPaths = [];

    // Preferred path: Flutter's official AssetManifest API. Immune to
    // the underlying manifest file format changing between SDK
    // versions, unlike hand-parsing AssetManifest.json.
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      allAssetPaths = manifest.listAssets();
    } catch (e) {
      // Fallback for older SDKs where AssetManifest isn't available.
      try {
        final raw = await rootBundle.loadString('AssetManifest.json');
        final decoded =
            raw.isNotEmpty ? (Uri.decodeFull(raw).isNotEmpty ? raw : raw) : raw;
        // Minimal manual parse without importing dart:convert twice —
        // handled below via a tiny local decode.
        allAssetPaths = _extractKeysFromRawJson(decoded);
      } catch (e2) {
        assert(() {
          // ignore: avoid_print
          print('CharacterIcons: could not load any asset manifest — $e / $e2');
          return true;
        }());
      }
    }

    for (final path in allAssetPaths) {
      final fileName = path.split('/').last;
      final lower = fileName.toLowerCase();
      if (!lower.startsWith('icon_')) continue;
      final withoutExt = fileName.replaceAll(RegExp(r'\.[a-zA-Z0-9]+$'), '');
      final afterPrefix = withoutExt.substring('icon_'.length);
      map[_normalize(afterPrefix)] = path;
    }

    assert(() {
      // ignore: avoid_print
      print(
          'CharacterIcons: found ${map.length} icon asset(s): ${map.keys.join(', ')}');
      return true;
    }());

    _byKey = map;
  }

  List<String> _extractKeysFromRawJson(String raw) {
    // Very small, dependency-free key extractor: AssetManifest.json is
    // a flat object of "path": [...] pairs — we only need the keys.
    final keys = <String>[];
    final regex = RegExp(r'"([^"]+)"\s*:\s*\[');
    for (final match in regex.allMatches(raw)) {
      final key = match.group(1);
      if (key != null) keys.add(key);
    }
    return keys;
  }

  /// Character-specific icon if one matches the name, else the
  /// per-team default, else null (caller shows colored initial).
  String? assetPathFor(ScriptCharacter character) {
    final byName = _byKey?[_normalize(character.name)];
    if (byName != null) return byName;
    return _byKey?[_normalize(character.team)];
  }

  /// Filename only (e.g. "icon_damsel.png") — used to serve the same
  /// assets to the browser client over HTTP.
  String? fileNameFor(ScriptCharacter character) {
    final path = assetPathFor(character);
    return path?.split('/').last;
  }
}
