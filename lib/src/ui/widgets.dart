import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart' show VideoTrack, VideoTrackRenderer, VideoViewFit, VideoViewMirrorMode;

import '../call/controller.dart';
import '../call/engine.dart';
import '../call/stage.dart';
import 'strings.dart';
import 'theme.dart';

/// Minimum touch target for every control.
const double teleMinTarget = 48;

/// A round control-bar button with a tooltip and a semantics label.
class TeleControlButton extends StatelessWidget {
  const TeleControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
    this.danger = false,
    this.toggled,
    this.badge,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// Filled with the accent colour.
  final bool active;
  final bool danger;

  /// For toggles: announced as pressed or not.
  final bool? toggled;

  /// A count shown on the button. Put it in [label] too, for screen readers.
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final bg = danger ? t.danger : (active ? t.accent : t.surface);
    final fg = danger ? t.onDanger : (active ? t.onAccent : t.text);
    final button = Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: Material(
        color: bg,
        shape: CircleBorder(side: BorderSide(color: danger || active ? bg : t.line)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox.square(dimension: teleMinTarget, child: Icon(icon, color: fg, size: 22)),
        ),
      ),
    );
    return Semantics(
      button: true,
      label: label,
      toggled: toggled,
      enabled: onPressed != null,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: badge != null && badge! > 0
            ? Badge(label: Text('${badge! > 99 ? '99+' : badge}'), backgroundColor: t.accent, textColor: t.onAccent, child: button)
            : button,
      ),
    );
  }
}

/// Initials for an avatar.
String teleInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = String.fromCharCodes(parts.first.runes.take(1));
  final last = parts.length > 1 ? String.fromCharCodes(parts.last.runes.take(1)) : '';
  return (first + last).toUpperCase();
}

class TeleAvatar extends StatelessWidget {
  const TeleAvatar({super.key, required this.name, this.size = 64});
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: t.accent.withValues(alpha: 0.18), shape: BoxShape.circle),
        child: Text(teleInitials(name), style: TextStyle(color: t.accent, fontSize: size * 0.36, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// A video if there is a track, else an avatar.
class TeleVideo extends StatelessWidget {
  const TeleVideo({super.key, required this.track, required this.name, this.mirror = false, this.contain = false});
  final VideoTrack? track;
  final String name;
  final bool mirror;
  final bool contain;

  @override
  Widget build(BuildContext context) {
    final t = track;
    if (t == null) return Center(child: TeleAvatar(name: name));
    return VideoTrackRenderer(
      t,
      key: ObjectKey(t),
      fit: contain ? VideoViewFit.contain : VideoViewFit.cover,
      mirrorMode: mirror ? VideoViewMirrorMode.mirror : VideoViewMirrorMode.off,
    );
  }
}

/// One participant's camera or screen share, with a name label and a pin button.
class TeleTileView extends StatelessWidget {
  const TeleTileView({
    super.key,
    required this.tile,
    required this.strings,
    required this.pinned,
    required this.speaking,
    required this.onTogglePin,
    this.canPin = true,
  });

  final TeleTile tile;
  final TeleStrings strings;
  final bool pinned;
  final bool speaking;
  final bool canPin;
  final VoidCallback onTogglePin;

  /// The name, with "(you)" and ", screen" as they apply.
  String get name {
    final p = tile.participant;
    final s = strings;
    var name = p.isLocal ? '${p.name}${s[TeleStringKey.youSuffix]}' : p.name;
    if (tile.screen) name += s[TeleStringKey.screenSuffix];
    return name;
  }

  String get label =>
      !tile.screen && !tile.participant.microphoneEnabled ? '$name${strings[TeleStringKey.mutedSuffix]}' : name;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final p = tile.participant;
    final track = tile.screen ? p.screenShareTrack : p.cameraTrack;
    final pinName = tile.screen ? '${p.name}${strings[TeleStringKey.screenSuffix]}' : p.name;
    final pinLabel = strings.format(pinned ? TeleStringKey.unpin : TeleStringKey.pin, {'name': pinName});
    return Semantics(
      container: true,
      label: label,
      selected: pinned,
      child: GestureDetector(
        onDoubleTap: canPin ? onTogglePin : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: t.tile,
            borderRadius: BorderRadius.circular(t.radius),
            border: Border.all(
              color: speaking ? t.accent : (pinned ? t.text.withValues(alpha: 0.5) : Colors.transparent),
              width: 3,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TeleVideo(track: track, name: p.name, mirror: p.isLocal && !tile.screen, contain: tile.screen),
              Positioned(
                left: 8,
                bottom: 8,
                right: 8,
                child: Row(
                  children: [
                    Flexible(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(t.radius / 2),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!tile.screen && !p.microphoneEnabled)
                              const Padding(
                                padding: EdgeInsets.only(right: 4),
                                child: Icon(Icons.mic_off, size: 14, color: Colors.white),
                              ),
                            Flexible(
                              child: ExcludeSemantics(
                                child: Text(label, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 13)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (canPin)
                Positioned(
                  top: 4,
                  right: 4,
                  child: Semantics(
                    container: true,
                    button: true,
                    toggled: pinned,
                    label: pinLabel,
                    excludeSemantics: true,
                    child: Tooltip(
                      message: pinLabel,
                      excludeFromSemantics: true,
                      child: Material(
                        color: Colors.black.withValues(alpha: 0.45),
                        shape: const CircleBorder(),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: onTogglePin,
                          child: SizedBox.square(
                            dimension: teleMinTarget,
                            child: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined, color: Colors.white, size: 20),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The large tile with a strip, or an even grid. Rebuilds on [TeleCallController.media] only.
///
/// Each tile keeps one [GlobalKey] while it is in the call, so moving between the stage, the strip
/// and the grid reparents its video renderer instead of recreating it (no black flash).
class TeleStageView extends StatefulWidget {
  const TeleStageView({super.key, required this.controller, required this.strings});
  final TeleCallController controller;
  final TeleStrings strings;

  @override
  State<TeleStageView> createState() => _TeleStageViewState();
}

class _TeleStageViewState extends State<TeleStageView> {
  final _keys = <String, GlobalKey>{};

  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: widget.controller.media, builder: _build);

  Widget _build(BuildContext context, Widget? _) {
    final controller = widget.controller;
    final stage = controller.stage;
    final speaking = controller.participants.where((p) => p.isSpeaking).map((p) => p.identity).toSet();
    final all = [?stage.focus, ...stage.rest];
    _keys.removeWhere((k, _) => !all.any((t) => t.key == k));
    final canPin = all.length > 1;
    Widget tile(TeleTile t) => TeleTileView(
          key: _keys.putIfAbsent(t.key, () => GlobalKey(debugLabel: t.key)),
          tile: t,
          strings: widget.strings,
          pinned: controller.pinned == t.key,
          speaking: !t.screen && speaking.contains(t.participant.identity),
          canPin: canPin,
          onTogglePin: () => controller.togglePinned(t.key),
        );

    return LayoutBuilder(builder: (context, box) {
      const gap = 8.0;
      final focus = stage.focus;
      if (focus != null) {
        final wide = box.maxWidth >= 900 || box.maxWidth > box.maxHeight * 1.6;
        final stripExtent = wide ? (box.maxWidth * 0.22).clamp(120.0, 260.0) : (box.maxHeight * 0.22).clamp(72.0, 120.0);
        // A plain scrollable row/column (not a lazy list) so each tile's state survives moves.
        final strip = SingleChildScrollView(
          scrollDirection: wide ? Axis.vertical : Axis.horizontal,
          child: Flex(
            direction: wide ? Axis.vertical : Axis.horizontal,
            children: [
              for (final (i, t) in stage.rest.indexed) ...[
                if (i > 0) const SizedBox.square(dimension: gap),
                SizedBox(
                  width: wide ? stripExtent : stripExtent * 1.6,
                  height: wide ? stripExtent / 1.6 : stripExtent,
                  child: tile(t),
                ),
              ],
            ],
          ),
        );
        final children = <Widget>[
          Expanded(child: tile(focus)),
          if (stage.rest.isNotEmpty) ...[
            const SizedBox.square(dimension: gap),
            SizedBox(width: wide ? stripExtent : null, height: wide ? null : stripExtent, child: strip),
          ],
        ];
        return wide ? Row(children: children) : Column(children: children);
      }
      final n = stage.rest.length;
      if (n == 0) return const SizedBox.shrink();
      final portrait = box.maxHeight > box.maxWidth;
      var cols = 1;
      while (cols * cols < n) {
        cols++;
      }
      if (portrait && n > 1) cols = n <= 2 ? 1 : (n <= 6 ? 2 : 3);
      final rows = (n / cols).ceil();
      return Column(
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) const SizedBox(height: gap),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) const SizedBox(width: gap),
                    Expanded(child: r * cols + c < n ? tile(stage.rest[r * cols + c]) : const SizedBox.shrink()),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    });
  }
}

/// Dropdowns for microphone, camera and (where the platform allows) speaker. The list refreshes
/// when devices change or become readable after a permission.
class TeleDevicePickers extends StatefulWidget {
  const TeleDevicePickers({super.key, required this.controller, required this.strings});
  final TeleCallController controller;
  final TeleStrings strings;

  @override
  State<TeleDevicePickers> createState() => _TeleDevicePickersState();
}

class _TeleDevicePickersState extends State<TeleDevicePickers> {
  List<TeleMediaDevice> _devices = const [];
  StreamSubscription<CallEngineEvent>? _sub;

  @override
  void initState() {
    super.initState();
    _load();
    _sub = widget.controller.engine.events.where((e) => e is CallEngineDevicesChanged).listen((_) => _load());
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await widget.controller.devices();
      if (mounted) setState(() => _devices = d);
    } catch (_) {
      // No device list on this platform; the pickers stay hidden.
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final s = widget.strings;
    final kinds = [
      (TeleMediaKind.audioInput, s[TeleStringKey.microphone], Icons.mic_none),
      (TeleMediaKind.videoInput, s[TeleStringKey.camera], Icons.videocam_outlined),
      if (widget.controller.engine.canSelectAudioOutput) (TeleMediaKind.audioOutput, s[TeleStringKey.speaker], Icons.volume_up_outlined),
    ];
    final pickers = <Widget>[];
    for (final (kind, label, icon) in kinds) {
      final list = _devices.where((d) => d.kind == kind).toList();
      if (list.length < 2) continue;
      final selected = list.where((d) => d.selected).firstOrNull ?? list.first;
      pickers.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DropdownButtonFormField<TeleMediaDevice>(
          key: ValueKey('$kind:${list.length}:${selected.id}'),
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, color: t.muted),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.radius / 2)),
          ),
          items: [
            for (final d in list)
              DropdownMenuItem(value: d, child: Text(d.label.isEmpty ? s[TeleStringKey.defaultDevice] : d.label, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (d) async {
            if (d == null) return;
            await widget.controller.selectDevice(d, label: label);
            await _load();
          },
        ),
      ));
    }
    if (pickers.isEmpty) return const SizedBox.shrink();
    return Column(mainAxisSize: MainAxisSize.min, children: pickers);
  }
}

/// Limits text to [max] Unicode code points, the way the Tele server counts message length.
class _CodePointLimit extends TextInputFormatter {
  const _CodePointLimit(this.max);
  final int max;

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) =>
      newValue.text.runes.length <= max ? newValue : oldValue;
}

/// The chat panel: history, live messages and an input.
class TeleChatPanel extends StatefulWidget {
  const TeleChatPanel({super.key, required this.controller, required this.strings, this.onClose});
  final TeleCallController controller;
  final TeleStrings strings;
  final VoidCallback? onClose;

  @override
  State<TeleChatPanel> createState() => _TeleChatPanelState();
}

class _TeleChatPanelState extends State<TeleChatPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  int _shown = 0;
  bool _first = true;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    // Keep the draft until it is sent; a failed send shows a notice and leaves it in the box.
    if (await widget.controller.sendChat(text) && mounted && _input.text == text) _input.clear();
  }

  bool get _nearBottom => !_scroll.hasClients || _scroll.position.maxScrollExtent - _scroll.position.pixels < 80;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final s = widget.strings;
    final messages = widget.controller.messages;
    // Follow new messages only when they arrive and the reader is already at the bottom (or they
    // are your own); scrolling up to read earlier messages isn't interrupted.
    if (messages.length > _shown) {
      final follow = _first || _nearBottom || messages.last.mine;
      _shown = messages.length;
      _first = false;
      if (follow) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
        });
      }
    }
    return Material(
      color: t.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(s[TeleStringKey.chat], style: TextStyle(color: t.text, fontSize: 17, fontWeight: FontWeight.w600)),
                  ),
                ),
                if (widget.onClose != null)
                  IconButton(
                    tooltip: s[TeleStringKey.closeChat],
                    constraints: const BoxConstraints(minWidth: teleMinTarget, minHeight: teleMinTarget),
                    icon: Icon(Icons.close, color: t.text),
                    onPressed: widget.onClose,
                  ),
              ],
            ),
          ),
          Divider(height: 1, color: t.line),
          Expanded(
            child: messages.isEmpty
                ? Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      child: Text(s[TeleStringKey.chatEmpty], textAlign: TextAlign.center, style: TextStyle(color: t.muted)),
                    ),
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    itemCount: messages.length,
                    itemBuilder: (_, i) => _Bubble(message: messages[i], youLabel: s[TeleStringKey.you]),
                  ),
          ),
          Divider(height: 1, color: t.line),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    inputFormatters: const [_CodePointLimit(teleChatMaxLength)],
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: TextStyle(color: t.text),
                    decoration: InputDecoration(
                      hintText: s[TeleStringKey.message],
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(t.radius)),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                IconButton.filled(
                  tooltip: s[TeleStringKey.send],
                  constraints: const BoxConstraints(minWidth: teleMinTarget, minHeight: teleMinTarget),
                  style: IconButton.styleFrom(backgroundColor: t.accent, foregroundColor: t.onAccent),
                  icon: const Icon(Icons.send),
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.youLabel});
  final TeleChatEntry message;
  final String youLabel;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final m = message;
    final who = m.mine ? youLabel : m.name;
    return Semantics(
      label: '$who: ${m.body}',
      excludeSemantics: true,
      child: Align(
        alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 320),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: m.mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Text(who, style: TextStyle(color: t.muted, fontSize: 12)),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: m.mine ? t.accent : t.tile,
                    borderRadius: BorderRadius.circular(t.radius * 0.75),
                  ),
                  child: SelectableText(m.body, style: TextStyle(color: m.mine ? t.onAccent : t.text)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-line banner (recording, reconnecting, device problems).
class TeleBanner extends StatelessWidget {
  const TeleBanner({
    super.key,
    required this.text,
    required this.icon,
    this.color,
    this.onDismiss,
    this.dismissLabel,
    this.onTap,
  });
  final String text;
  final IconData icon;
  final Color? color;
  final VoidCallback? onDismiss;
  final String? dismissLabel;

  /// Makes the whole banner a button (for example "Tap to turn on call audio").
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = TeleCallTheme.of(context);
    final c = color ?? t.text;
    final body = Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: EdgeInsets.only(left: 12, right: onDismiss == null ? 12 : 0),
      decoration: BoxDecoration(
        color: Color.alphaBlend(c.withValues(alpha: 0.14), t.surface),
        borderRadius: BorderRadius.circular(t.radius / 2),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: c),
          const SizedBox(width: 8),
          Expanded(child: Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(color: t.text))),
          if (onDismiss != null)
            IconButton(
              tooltip: dismissLabel,
              constraints: const BoxConstraints(minWidth: teleMinTarget, minHeight: teleMinTarget),
              icon: Icon(Icons.close, size: 18, color: t.muted),
              onPressed: onDismiss,
            ),
        ],
      ),
    );
    return Semantics(
      liveRegion: true,
      container: true,
      button: onTap != null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: onTap == null
            ? body
            : Material(
                color: Colors.transparent,
                child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(t.radius / 2), child: body),
              ),
      ),
    );
  }
}
