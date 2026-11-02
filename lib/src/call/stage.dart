import 'engine.dart';

enum TeleLayout {
  /// Even tiles.
  grid,

  /// The active speaker large, the others in a strip.
  speaker,
}

/// One video tile: a participant's camera, or a screen share.
class TeleTile {
  const TeleTile(this.participant, {this.screen = false});
  final CallParticipant participant;
  final bool screen;

  bool get local => participant.isLocal;

  /// `identity:camera` or `identity:screen_share`. Pins refer to this key.
  String get key => tileKey(participant.identity, screen: screen);
}

String tileKey(String identity, {bool screen = false}) => '$identity:${screen ? 'screen_share' : 'camera'}';

/// What the stage shows: [focus] large (null means an even grid) and [rest] in the strip or grid.
class TeleStage {
  const TeleStage(this.focus, this.rest);
  final TeleTile? focus;
  final List<TeleTile> rest;
}

/// Camera tiles for everyone plus a tile per active screen share.
List<TeleTile> tilesFor(List<CallParticipant> participants) => [
      for (final p in participants) ...[TeleTile(p), if (p.hasScreenShare) TeleTile(p, screen: true)],
    ];

/// Decides what takes the stage, in order:
/// 1. the tile this viewer pinned, if it is still in the call;
/// 2. someone else's screen share (your own stays small unless you pin it);
/// 3. in speaker layout, [speaker] (the active speaker's camera tile key), else the first remote tile;
/// 4. otherwise an even grid.
///
/// Nothing is focused when there is only one tile.
TeleStage arrangeStage(List<TeleTile> tiles, {required TeleLayout layout, String? pinned, String? speaker}) {
  TeleStage? pick(String? key) {
    if (key == null || tiles.length < 2) return null;
    final i = tiles.indexWhere((t) => t.key == key);
    if (i < 0) return null;
    return TeleStage(tiles[i], [...tiles.take(i), ...tiles.skip(i + 1)]);
  }

  String? firstKey(bool Function(TeleTile) test) {
    for (final t in tiles) {
      if (test(t)) return t.key;
    }
    return null;
  }

  return pick(pinned) ??
      pick(firstKey((t) => t.screen && !t.local)) ??
      (layout == TeleLayout.speaker ? pick(speaker) ?? pick(firstKey((t) => !t.local)) : null) ??
      TeleStage(null, tiles);
}

/// Pinning the tile that is already pinned unpins it.
String? togglePin(String? pinned, String key) => pinned == key ? null : key;
