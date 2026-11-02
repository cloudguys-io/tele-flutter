import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Colours and shape of the call screen. Add it to your `ThemeData.extensions`, or pass it to
/// `TeleCallScreen.theme`. Without one, the screen uses [TeleCallTheme.light] or [TeleCallTheme.dark]
/// following the ambient brightness.
@immutable
class TeleCallTheme extends ThemeExtension<TeleCallTheme> {
  const TeleCallTheme({
    required this.accent,
    required this.onAccent,
    required this.radius,
    required this.background,
    required this.surface,
    required this.tile,
    required this.text,
    required this.muted,
    required this.line,
    required this.danger,
    required this.onDanger,
  });

  /// Vermilion accent and warm neutrals, matching the web call UI.
  static const light = TeleCallTheme(
    accent: Color(0xFFC6432A),
    onAccent: Colors.white,
    radius: 16,
    background: Color(0xFFF7F5F2),
    surface: Colors.white,
    tile: Color(0xFFE7E3DE),
    text: Color(0xFF1C1A17),
    muted: Color(0xFF6B655E),
    line: Color(0xFFDDD8D1),
    danger: Color(0xFFC62828),
    onDanger: Colors.white,
  );

  static const dark = TeleCallTheme(
    accent: Color(0xFFF07A5F),
    onAccent: Color(0xFF1C0F0B),
    radius: 16,
    background: Color(0xFF141311),
    surface: Color(0xFF1F1D1A),
    tile: Color(0xFF2A2724),
    text: Color(0xFFF2EFEA),
    muted: Color(0xFFA59E95),
    line: Color(0xFF38342F),
    danger: Color(0xFFEF5350),
    onDanger: Color(0xFF1A0606),
  );

  final Color accent;
  final Color onAccent;

  /// Tile corner radius; smaller elements scale from it.
  final double radius;
  final Color background;
  final Color surface;
  final Color tile;
  final Color text;
  final Color muted;
  final Color line;
  final Color danger;
  final Color onDanger;

  static TeleCallTheme of(BuildContext context) =>
      Theme.of(context).extension<TeleCallTheme>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  TeleCallTheme copyWith({
    Color? accent,
    Color? onAccent,
    double? radius,
    Color? background,
    Color? surface,
    Color? tile,
    Color? text,
    Color? muted,
    Color? line,
    Color? danger,
    Color? onDanger,
  }) =>
      TeleCallTheme(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
        radius: radius ?? this.radius,
        background: background ?? this.background,
        surface: surface ?? this.surface,
        tile: tile ?? this.tile,
        text: text ?? this.text,
        muted: muted ?? this.muted,
        line: line ?? this.line,
        danger: danger ?? this.danger,
        onDanger: onDanger ?? this.onDanger,
      );

  @override
  TeleCallTheme lerp(TeleCallTheme? other, double t) {
    if (other == null) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return TeleCallTheme(
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      radius: lerpDouble(radius, other.radius, t)!,
      background: c(background, other.background),
      surface: c(surface, other.surface),
      tile: c(tile, other.tile),
      text: c(text, other.text),
      muted: c(muted, other.muted),
      line: c(line, other.line),
      danger: c(danger, other.danger),
      onDanger: c(onDanger, other.onDanger),
    );
  }
}
